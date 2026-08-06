import json
import logging
import os
import tempfile
import uuid

from fastapi import APIRouter, Depends, Form, UploadFile, File, HTTPException, BackgroundTasks
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.models import Book, Annotation, ReadingProgress, ReadingSession, Activity, shelf_books, User
from app.core.storage import upload_file, get_presigned_url, upload_bytes, delete_file, download_bytes
from app.core.extraction.pipeline import run_pipeline
from app.core.cover_fetch import fetch_cover
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

    manual_cover_saved = False
    if cover is not None:
        cover_contents = await cover.read()
        if cover_contents:
            cover_key = f"covers/{user.id}/{book.id}.jpg"
            upload_bytes(cover_contents, cover_key, content_type=cover.content_type or "image/jpeg")
            book.cover_key = cover_key
            db.commit()
            manual_cover_saved = True

    # Extraction runs async so upload responds immediately -- large PDFs can
    # take a while to process, especially if OCR is needed. The background
    # task opens its own DB session, so the request session isn't passed.
    background_tasks.add_task(process_extraction, book.id, tmp_path)

    # No manual cover was attached -- try to find the real published cover
    # by title/author in the background. If nothing is found, cover_key
    # simply stays unset; we never fabricate a placeholder here.
    if not manual_cover_saved:
        background_tasks.add_task(fetch_and_store_cover, book.id, title, author)

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
        book.extraction_progress = 0
        db.commit()

        def set_progress(fraction: float):
            pct = int(round(fraction * 100))
            _extraction_progress[book_id] = pct
            # Persist every integer-percent change so progress survives a
            # process recycle (Render free tier can sleep/restart mid-job).
            if book.extraction_progress != pct:
                book.extraction_progress = pct
                db.commit()

        set_progress(0.01)

        def upload_page_image(data: bytes, ext: str) -> str:
            import uuid as _uuid

            key = f"images/{book.owner_id}/{book_id}/{_uuid.uuid4().hex}.{ext}"
            upload_bytes(data, storage_key=key, content_type="image/jpeg" if ext == "jpg" else "image/png")
            return key

        import time as _time
        _job_started = _time.perf_counter()
        result = run_pipeline(local_pdf_path, progress_cb=set_progress, image_uploader=upload_page_image)
        logger.info(
            "Extraction finished for book %s in %.2fs: %d pages, images=%d",
            book_id,
            _time.perf_counter() - _job_started,
            len(result["pages"]),
            sum(len(p.get("images", [])) for p in result["pages"]),
        )
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


async def fetch_and_store_cover(book_id: str, title: str, author: str):
    """Look up a real cover by title/author and store it, if one is found.

    Runs independently of process_extraction -- a slow or failed cover
    lookup should never hold up or fail the extraction pipeline, and vice
    versa. Opens its own DB session for the same reason process_extraction
    does: the request-scoped session is already closed by the time
    background tasks run.
    """
    try:
        result = await fetch_cover(title, author)
    except Exception as exc:  # best-effort: never let a lookup bug surface to the user
        logger.info("Cover lookup errored for book %s: %s", book_id, exc)
        return

    if not result:
        return  # no match found -- leave cover_key unset, no placeholder

    image_bytes, content_type = result
    db = SessionLocal()
    try:
        book = db.query(Book).filter(Book.id == book_id).first()
        if not book or book.cover_key:
            # Book was deleted, or a manual/earlier cover already landed
            # first -- don't clobber it.
            return
        ext = "png" if "png" in content_type else "jpg"
        cover_key = f"covers/{book.owner_id}/{book.id}.{ext}"
        upload_bytes(image_bytes, cover_key, content_type=content_type)
        book.cover_key = cover_key
        db.commit()
    finally:
        db.close()


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


@router.get("/progress")
def list_progress(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Reading progress for every book the user owns, in one call.

    The mobile app uses this instead of one request per book, so refreshing
    the library is a constant number of requests rather than O(N).
    Registered before ``/{book_id}`` so the static path isn't shadowed.
    """
    rows = (
        db.query(ReadingProgress)
        .filter(ReadingProgress.user_id == user.id)
        .all()
    )
    return [
        {
            "book_id": r.book_id,
            "current_page": r.current_page,
            "current_offset": r.current_offset,
        }
        for r in rows
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
        progress = _extraction_progress.get(book_id) or book.extraction_progress or 0
    return {"extraction_status": status, "progress": progress}


@router.post("/{book_id}/re-extract")
def re_extract_book(
    book_id: str,
    background_tasks: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Re-run extraction for a book whose stored JSON predates the text-layer
    engine (legacy reflow format, no ``runs``). Downloads the original PDF
    from object storage and processes it into ``textlayer-v1`` in the
    background, replacing the stored JSON and confidence columns. The caller
    can watch ``GET /books/{id}/progress`` while it runs."""
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.owner_id != user.id:
        raise HTTPException(status_code=403, detail="Not your book")
    if book.extraction_status == "processing":
        raise HTTPException(status_code=409, detail="Extraction already in progress")

    try:
        pdf_bytes = download_bytes(book.storage_key)
    except Exception as exc:
        logger.exception("Could not download PDF for re-extract %s: %s", book_id, exc)
        raise HTTPException(status_code=400, detail="Could not read the original PDF")

    with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
        tmp.write(pdf_bytes)
        tmp_path = tmp.name

    # Flip the status synchronously so an immediate /progress poll reports
    # "processing" instead of racing the background task's own flip.
    book.extraction_status = "processing"
    book.extraction_progress = 0
    db.commit()
    background_tasks.add_task(process_extraction, book.id, tmp_path)

    return {"id": book.id, "status": "processing", "extraction_status": "processing"}


@router.get("/{book_id}/images")
def get_book_images(book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Per-page placed images with fresh presigned URLs, for the web reader.

    Image storage keys live in the structured text JSON (``pages[].images[]``);
    they are not directly usable as browser URLs, so the reader asks for them
    here instead of embedding long-lived URLs in the cached JSON."""
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.owner_id != user.id:
        raise HTTPException(status_code=403, detail="Not your book")
    if not book.structured_text_key:
        return {"pages": []}

    try:
        raw = download_bytes(book.structured_text_key)
    except Exception as exc:
        logger.warning("Could not read structured text for book %s: %s", book_id, exc)
        return {"pages": []}

    try:
        data = json.loads(raw)
    except Exception:
        return {"pages": []}

    pages = []
    for p in data.get("pages", []):
        images = []
        for img in p.get("images", []):
            key = img.get("key")
            if not key:
                continue
            images.append(
                {
                    "x": img.get("x"),
                    "y": img.get("y"),
                    "w": img.get("w"),
                    "h": img.get("h"),
                    "url": get_presigned_url(key, inline=True),
                }
            )
        pages.append({"page": p.get("page"), "images": images})
    return {"pages": pages}


class BookUpdate(BaseModel):
    title: str | None = None
    author: str | None = None
    genre: str | None = None


@router.put("/{book_id}")
def update_book(
    book_id: str,
    body: BookUpdate,
    background_tasks: BackgroundTasks,
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

    # The book still has no cover -- kick off a background cover lookup with
    # the (possibly corrected) title/author so a re-save on a coverless book
    # retries it. Same rules as upload: never clobber an existing cover,
    # never fabricate a placeholder when there's no match.
    if not book.cover_key:
        background_tasks.add_task(fetch_and_store_cover, book.id, book.title, book.author or "")

    return {"id": book.id, "status": "updated"}


@router.put("/{book_id}/cover")
def update_book_cover(
    book_id: str,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Replace a book's cover image."""
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.owner_id != user.id:
        raise HTTPException(status_code=403, detail="Not your book")

    contents = file.file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty file")

    # Match the key to the actual image type. The auto-fetch stores JPEGs at
    # `covers/{user}/{book_id}.jpg`, so a PNG upload must use a different key
    # than the cover it replaces -- and a JPEG replacement reuses the existing
    # key (overwriting it in place) instead of deleting its own file.
    content_type = file.content_type or "image/jpeg"
    ext = "png" if content_type.lower().startswith("image/png") else "jpg"
    storage_key = f"covers/{user.id}/{book_id}.{ext}"
    upload_bytes(contents, storage_key, content_type=content_type)

    old_key = book.cover_key
    book.cover_key = storage_key
    db.commit()
    if old_key and old_key != storage_key:
        try:
            delete_file(old_key)
        except Exception:
            pass
    return {"cover_url": get_presigned_url(storage_key)}


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
