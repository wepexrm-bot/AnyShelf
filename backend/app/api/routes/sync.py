from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.routes.auth import get_current_user
from app.core.models import ReadingProgress, Annotation, User
from app.db.database import get_db

router = APIRouter()


class ProgressUpdate(BaseModel):
    book_id: str
    current_page: float
    current_offset: float = 0


@router.post("/progress")
def update_progress(body: ProgressUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = user.id
    progress = (
        db.query(ReadingProgress)
        .filter(ReadingProgress.user_id == user_id, ReadingProgress.book_id == body.book_id)
        .first()
    )
    if progress:
        progress.current_page = body.current_page
        progress.current_offset = body.current_offset
    else:
        progress = ReadingProgress(
            user_id=user_id, book_id=body.book_id, current_page=body.current_page, current_offset=body.current_offset
        )
        db.add(progress)

    db.commit()
    return {"status": "synced"}


@router.get("/progress/{book_id}")
def get_progress(book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = user.id
    progress = (
        db.query(ReadingProgress)
        .filter(ReadingProgress.user_id == user_id, ReadingProgress.book_id == book_id)
        .first()
    )
    if not progress:
        return {"current_page": 0, "current_offset": 0}

    return {"current_page": progress.current_page, "current_offset": progress.current_offset}


class AnnotationCreate(BaseModel):
    book_id: str
    kind: str  # "highlight" | "note" | "bookmark"
    anchor: str = ""
    color: str | None = None
    note_text: str | None = None


@router.post("/annotations")
def create_annotation(body: AnnotationCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    annotation = Annotation(
        user_id=user.id,
        book_id=body.book_id,
        kind=body.kind,
        anchor=body.anchor,
        color=body.color,
        note_text=body.note_text,
    )
    db.add(annotation)
    db.commit()
    db.refresh(annotation)
    return {"id": annotation.id}


@router.get("/annotations/{book_id}")
def list_annotations(book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    annotations = (
        db.query(Annotation)
        .filter(Annotation.user_id == user.id, Annotation.book_id == book_id)
        .all()
    )
    return [
        {
            "id": a.id,
            "kind": a.kind,
            "anchor": a.anchor,
            "color": a.color,
            "note_text": a.note_text,
        }
        for a in annotations
    ]


@router.delete("/annotations/{annotation_id}")
def delete_annotation(
    annotation_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    annotation = (
        db.query(Annotation)
        .filter(Annotation.id == annotation_id, Annotation.user_id == user.id)
        .first()
    )
    if not annotation:
        raise HTTPException(status_code=404, detail="Annotation not found")
    db.delete(annotation)
    db.commit()
    return {"status": "deleted"}
