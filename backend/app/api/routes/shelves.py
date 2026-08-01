from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.routes.auth import get_current_user
from app.core.models import Book, Shelf, ShelfFollow, User
from app.core.storage import upload_bytes, get_presigned_url, delete_file
from app.db.database import get_db

router = APIRouter()


class ShelfCreate(BaseModel):
    name: str
    description: str | None = None
    is_public: bool = False
    color: str | None = None
    banner_key: str | None = None


class ShelfUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    is_public: bool | None = None
    color: str | None = None
    banner_key: str | None = None


def _shelf_to_dict(shelf: Shelf, book_count: int | None = None) -> dict:
    return {
        "id": shelf.id,
        "name": shelf.name,
        "description": shelf.description,
        "is_public": shelf.is_public,
        "color": shelf.color,
        "banner_url": get_presigned_url(shelf.banner_key) if shelf.banner_key else None,
        "book_count": book_count if book_count is not None else len(shelf.books),
        "created_at": shelf.created_at,
    }


def _get_owned_shelf(db: Session, shelf_id: str, owner_id: str) -> Shelf:
    shelf = db.query(Shelf).filter(Shelf.id == shelf_id).first()
    if not shelf:
        raise HTTPException(status_code=404, detail="Shelf not found")
    if shelf.owner_id != owner_id:
        raise HTTPException(status_code=403, detail="Not your shelf")
    return shelf


@router.get("/")
def list_shelves(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelves = db.query(Shelf).filter(Shelf.owner_id == user.id).order_by(Shelf.created_at.desc()).all()
    result = []
    for s in shelves:
        item = _shelf_to_dict(s)
        item["book_ids"] = [b.id for b in s.books]
        result.append(item)
    return result


@router.post("/")
def create_shelf(body: ShelfCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = Shelf(
        owner_id=user.id,
        name=body.name,
        description=body.description,
        is_public=body.is_public,
        color=body.color,
        banner_key=body.banner_key,
    )
    db.add(shelf)
    db.commit()
    db.refresh(shelf)
    return _shelf_to_dict(shelf)


@router.get("/{shelf_id}")
def get_shelf(shelf_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = _get_owned_shelf(db, shelf_id, user.id)
    return {
        **_shelf_to_dict(shelf),
        "books": [
            {
                "id": b.id,
                "title": b.title,
                "extraction_status": b.extraction_status,
                "reflow_confidence": b.reflow_confidence,
            }
            for b in shelf.books
        ],
    }


@router.put("/{shelf_id}")
def update_shelf(shelf_id: str, body: ShelfUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = _get_owned_shelf(db, shelf_id, user.id)
    if body.name is not None:
        shelf.name = body.name
    if body.description is not None:
        shelf.description = body.description
    if body.is_public is not None:
        shelf.is_public = body.is_public
    if body.color is not None:
        shelf.color = body.color
    if body.banner_key is not None:
        shelf.banner_key = body.banner_key
    db.commit()
    db.refresh(shelf)
    return _shelf_to_dict(shelf)


@router.post("/{shelf_id}/banner")
def upload_shelf_banner(
    shelf_id: str,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    shelf = _get_owned_shelf(db, shelf_id, user.id)
    contents = file.file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty file")

    storage_key = f"banners/{user.id}/{shelf_id}.jpg"
    upload_bytes(contents, storage_key, content_type=file.content_type or "image/jpeg")

    old_key = shelf.banner_key
    shelf.banner_key = storage_key
    db.commit()
    if old_key:
        try:
            delete_file(old_key)
        except Exception:
            pass
    return {"banner_url": get_presigned_url(storage_key)}


@router.delete("/{shelf_id}")
def delete_shelf(shelf_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = _get_owned_shelf(db, shelf_id, user.id)
    db.delete(shelf)
    db.commit()
    return {"status": "deleted"}


@router.post("/{shelf_id}/books/{book_id}")
def add_book(shelf_id: str, book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = _get_owned_shelf(db, shelf_id, user.id)
    book = db.query(Book).filter(Book.id == book_id).first()
    if not book:
        raise HTTPException(status_code=404, detail="Book not found")
    if book not in shelf.books:
        shelf.books.append(book)
        db.commit()
    return _shelf_to_dict(shelf)


@router.delete("/{shelf_id}/books/{book_id}")
def remove_book(shelf_id: str, book_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = _get_owned_shelf(db, shelf_id, user.id)
    book = db.query(Book).filter(Book.id == book_id).first()
    if book in shelf.books:
        shelf.books.remove(book)
        db.commit()
    return _shelf_to_dict(shelf)


@router.get("/shared/all")
def list_public_shelves(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelves = (
        db.query(Shelf)
        .filter(Shelf.is_public == True, Shelf.owner_id != user.id)  # noqa: E712
        .order_by(Shelf.created_at.desc())
        .limit(50)
        .all()
    )
    result = []
    for s in shelves:
        item = _shelf_to_dict(s)
        item["owner_display_name"] = s.owner.display_name if s.owner else None
        item["followed"] = bool(
            db.query(ShelfFollow).filter(ShelfFollow.user_id == user.id, ShelfFollow.shelf_id == s.id).first()
        )
        result.append(item)
    return result


@router.post("/{shelf_id}/follow")
def follow_shelf(shelf_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    shelf = db.query(Shelf).filter(Shelf.id == shelf_id).first()
    if not shelf:
        raise HTTPException(status_code=404, detail="Shelf not found")
    existing = (
        db.query(ShelfFollow).filter(ShelfFollow.user_id == user.id, ShelfFollow.shelf_id == shelf_id).first()
    )
    if not existing:
        db.add(ShelfFollow(user_id=user.id, shelf_id=shelf_id))
        db.commit()
    return {"status": "followed"}


@router.delete("/{shelf_id}/follow")
def unfollow_shelf(shelf_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    existing = (
        db.query(ShelfFollow).filter(ShelfFollow.user_id == user.id, ShelfFollow.shelf_id == shelf_id).first()
    )
    if existing:
        db.delete(existing)
        db.commit()
    return {"status": "unfollowed"}
