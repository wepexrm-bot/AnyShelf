from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.routes.auth import get_current_user
from app.core.models import Activity, Book, Follow, Shelf, User
from app.db.database import get_db

router = APIRouter()


class FollowBody(BaseModel):
    user_id: str


def _user_to_dict(u: User) -> dict:
    return {"id": u.id, "display_name": u.display_name, "email": u.email}


def _activity_to_dict(a: Activity, db: Session) -> dict:
    book = db.query(Book).filter(Book.id == a.book_id).first() if a.book_id else None
    shelf = db.query(Shelf).filter(Shelf.id == a.shelf_id).first() if a.shelf_id else None
    author = db.query(User).filter(User.id == a.user_id).first()
    return {
        "id": a.id,
        "kind": a.kind,
        "text": a.text,
        "created_at": a.created_at,
        "author": _user_to_dict(author) if author else {"id": a.user_id, "display_name": "Reader"},
        "book": {"id": book.id, "title": book.title} if book else None,
        "shelf": {"id": shelf.id, "name": shelf.name} if shelf else None,
    }


@router.post("/follow")
def follow_user(body: FollowBody, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = user.id
    if body.user_id == user_id:
        raise HTTPException(status_code=400, detail="Cannot follow yourself")
    target = db.query(User).filter(User.id == body.user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    existing = (
        db.query(Follow).filter(Follow.follower_id == user_id, Follow.following_id == body.user_id).first()
    )
    if not existing:
        db.add(Follow(follower_id=user_id, following_id=body.user_id))
        db.commit()
    return {"status": "following"}


@router.delete("/follow/{target_id}")
def unfollow_user(target_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = user.id
    existing = (
        db.query(Follow).filter(Follow.follower_id == user_id, Follow.following_id == target_id).first()
    )
    if existing:
        db.delete(existing)
        db.commit()
    return {"status": "unfollowed"}


@router.get("/following")
def list_following(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = (
        db.query(User)
        .join(Follow, Follow.following_id == User.id)
        .filter(Follow.follower_id == user.id)
        .all()
    )
    return [_user_to_dict(u) for u in rows]


class ActivityCreate(BaseModel):
    kind: str  # finished | highlighted | shelf_shared | reviewed
    book_id: str | None = None
    shelf_id: str | None = None
    text: str | None = None


@router.post("/activity")
def create_activity(body: ActivityCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    allowed = {"finished", "highlighted", "shelf_shared", "reviewed"}
    if body.kind not in allowed:
        raise HTTPException(status_code=400, detail=f"kind must be one of {sorted(allowed)}")
    activity = Activity(
        user_id=user.id,
        kind=body.kind,
        book_id=body.book_id,
        shelf_id=body.shelf_id,
        text=body.text,
    )
    db.add(activity)
    db.commit()
    db.refresh(activity)
    return _activity_to_dict(activity, db)


@router.get("/activity")
def get_activity_feed(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Community feed: my activity plus activity from people I follow."""
    user_id = user.id
    following_ids = [
        row.following_id for row in db.query(Follow).filter(Follow.follower_id == user_id).all()
    ]
    feed_users = [user_id, *following_ids]

    activities = (
        db.query(Activity)
        .filter(Activity.user_id.in_(feed_users))
        .order_by(Activity.created_at.desc())
        .limit(50)
        .all()
    )
    return [_activity_to_dict(a, db) for a in activities]
