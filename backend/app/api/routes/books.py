import json
import logging
import os
import tempfile
import uuid

from fastapi import APIRouter, Depends, Form, UploadFile, File, HTTPException, BackgroundTasks
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.models import Book, Annotation, ReadingProgress, ReadingSession, Activity, shelf_books, User
from app.core.storage import upload_file, get_presigned_url, upload_bytes, delete_file
from app.core.extraction.pipeline import run_pipeline
from app.api.routes.auth import get_current_user
from app.db.database import get_db, SessionLocal

router = APIRouter()
logger = logging.getLogger("cloudread.books")

# Live extraction progress, keyed by book id. Only populated while a
# background extraction is running in this process; cleared on completion.
_extraction_progress: dict[str, int] = {}


@router.post("/upload")
async def upload_book(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    title: str = Form(...),
    author: str = Form(...),
    genre: str | None = Form(default=None),
    cover: UploadFile | None = File(default=None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    title = title.strip()
    author = author.strip()
    genre = (genre or "").strip() or None
    if not title:
        raise HTTPException(status_code=400, detail="Book name is required")
    if not author:
        raise HTTPException(status_code=400, detail="Author is required")
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported")

    with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    storage_key = f"books/{user.id}/{uuid.uuid4()}.pdf"
    upload_file(tmp_path, storage_key, content_type="application/pdf")

    book = Book(
        owner_id=user.id,
        title=title,
        author=author,
        genre=genre,
        original_filename=file.filename,
        storage_key=storage_key,
        extraction_status="pending",
    )
    db.add(book)
    db.commit()
    db.refresh(book)

    if cover is not None:
        cover_contents = await cover.read()
        if cover_contents:
            cover_key = f"covers/{user.id}/{book.id}.jpg"
            upload_bytes(cover_contents, cover_key, content_type=cover.content_type or "image/jpeg")
            book.cover_key = cover_key
            db.commit()

    # Extraction runs async so upload responds immediately -- large PDFs can
    # take a while to process, especially if OCR is needed. The background
    # task opens its own DB session, so the request session isn't passed.
    background_tasks.add_task(process_extraction, book.id, tmp_path)

    return {
        "book_id": book.id,
        "status": "uploaded",
        "extraction_status": "pending",
        "author": book.author,
        "genre": book.genre,
    }


def _import_pdf_native_annotations(db: Session, book: Book, annotations: list[dict]):
    """Replace the book's previously-imported native annotations with a fresh
    set, storing each as an Annotation row anchored by its matched text."""
    if not annotations:
        return
    db.query(Annotation).filter(
        Annotation.book_id == book.id,
        Annotation.source == "pdf_native",
    ).delete(synchronize_session=False)

    for ann in annotations:
        db.add(
            Annotation(
                user_id=book.owner_id,
                book_id=book.id,
                kind=ann["kind"] if ann["kind"] in ("highlight", "note") else "highlight",
                source="pdf_native",
                anchor=json.dumps(ann["anchor"], ensure_ascii=False),
                page=ann["page"],
                color=ann["color"],
                note_text=ann["note"],
            )
        )


def process_extraction(book_id: str, local_pdf_path: str):
    """Run extraction in the background.

    Opens its own DB session rather than reusing the request-scoped one,
    which FastAPI closes as soon as the upload response is returned --
    reusing it caused background tasks to fail on a closed session.
    """
    db = SessionLocal()
    try:
        book = db.query(Book).filter(Book.id == book_id).first()
        if not book:
            return

        book.extraction_status = "processing"
        db.commit()

        def set_progress(fraction: float):
            _extraction_progress[book_id] = int(round(fraction * 100))

        set_progress(0.01)
        result = run_pipeline(local_pdf_path, progress_cb=set_progress)
        set_progress(1.0)

        structured_key = f"structured/{book.owner_id}/{book_id}.json"
        upload_bytes(
            data=json.dumps(result).encode("utf-8"),
            storage_key=structured_key,
            content_type="application/json",
        )

        book.structured_text_key = structured_key
        book.reflow_confidence = result["reflow_confidence"]
        book.is_scanned = result["is_scanned"]
        book.page_count = len(result["pages"])
        book.extraction_status = "done"

        # Import native PDF annotations (highlights / margin notes) as
        # text-anchored rows owned by the book's owner. Re-running the job
        # replaces the previous import, never duplicating.
        _import_pdf_native_annotations(db, book, result.get("imported_annotations", []))

        db.commit()
        _extraction_progress.pop(book_id, None)
    except Exception as exc:
        logger.exception("Extraction failed for book %s: %s", book_id, exc)
        if db.is_active:
            book = db.get(Book, book_id)
            if book:
                book.extraction_status = "failed"
                db.commit()
        _extraction_progress.pop(book_id, None)
    finally:
        db.close()
        try:
            os.remove(local_pdf_path)
        except OSError:
            pass


@router.get("/")
def list_books(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    books = (
        db.query(Book)
        .filter(Book.owner_id == user.id)
        .order_by(Book.created_at.desc())
        .all()
    )
    return [
        {
            "id": b.id,
            "title": b.title,
            "author": b.author,
            "genre": b.genre,
            "cover_url": get_presigned_url(b.cover_key) if b.cover_key else None,
            "extraction_status": b.extraction_status,
            "reflow_confidence": b.reflow_confidence,
            "is_scanned": b.is_scanned,
            "created_at": b.created_at.isoformat() if b.created_at else None,
        }
        for b in books
    ]


@router.get("/{book_id}/progress")
def get_extraction_progress(
    book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.owner_id != user.id:
        raise HTTPException(status_code=403, detail="Not your book")

    status = book.extraction_status
    if status == "done":
        progress = 100
    elif status == "failed":
        progress = 0
    else:
        progress = _extraction_progress.get(book_id, 0)
    return {"extraction_status": status, "progress": progress}


class BookUpdate(BaseModel):
    title: str | None = None
    author: str | None = None
    genre: str | None = None


@router.put("/{book_id}")
def update_book(
    book_id: str,
    body: BookUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Edit a book's metadata (title / author / genre)."""
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.owner_id != user.id:
        raise HTTPException(status_code=403, detail="Not your book")

    if body.title is not None and body.title.strip():
        book.title = body.title.strip()
    if body.author is not None:
        book.author = body.author.strip() or None
    if body.genre is not None:
        book.genre = body.genre.strip() or None
    db.commit()
    return {"id": book.id, "status": "updated"}


@router.get("/{book_id}")
def get_book(book_id: str, db: Session = Depends(get_db)):
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")

    return {
        "id": book.id,
        "title": book.title,
        "author": book.author,
        "genre": book.genre,
        "cover_url": get_presigned_url(book.cover_key) if book.cover_key else None,
        "extraction_status": book.extraction_status,
        "reflow_confidence": book.reflow_confidence,
        "is_scanned": book.is_scanned,
        "pdf_url": get_presigned_url(book.storage_key, inline=True),
        "structured_text_url": get_presigned_url(book.structured_text_key) if book.structured_text_key else None,
    }


@router.delete("/{book_id}")
def delete_book(book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Delete a book and everything referencing it: the PDF + structured JSON
    in object storage, and DB rows (annotations, progress, shelf links)."""
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.owner_id != user.id:
        raise HTTPException(status_code=403, detail="Not your book")

    try:
        delete_file(book.storage_key)
        if book.structured_text_key:
            delete_file(book.structured_text_key)
        if book.cover_key:
            delete_file(book.cover_key)
    except Exception as exc:
        logger.warning("Could not delete storage files for book %s: %s", book_id, exc)

    # Remove FK references before dropping the book row itself.
    db.query(Annotation).filter(Annotation.book_id == book_id).delete(synchronize_session=False)
    db.query(ReadingProgress).filter(ReadingProgress.book_id == book_id).delete(synchronize_session=False)
    db.query(ReadingSession).filter(ReadingSession.book_id == book_id).delete(synchronize_session=False)
    db.query(Activity).filter(Activity.book_id == book_id).delete(synchronize_session=False)
    db.execute(shelf_books.delete().where(shelf_books.c.book_id == book_id))

    db.delete(book)
    db.commit()
    return {"status": "deleted"}
