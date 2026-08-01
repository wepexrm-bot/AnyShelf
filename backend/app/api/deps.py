"""Shared auth/identity dependencies.

Until real auth is enforced on every route, routes fall back to a single
seeded demo user. A full implementation would read the JWT from the
Authorization header and return the authenticated user.
"""

from app.core.models import User

DEMO_USER_ID = "00000000-0000-0000-0000-000000000001"


def get_current_user_id() -> str:
    return DEMO_USER_ID


def ensure_user(db, user_id: str) -> User:
    user = db.get(User, user_id)
    if not user:
        user = User(
            id=user_id,
            email=f"{user_id}@demo.local",
            hashed_password="x",
            display_name="Demo User",
        )
        db.add(user)
        db.commit()
    return user
