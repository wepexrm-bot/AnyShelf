"""Reading stats: overview, monthly progress, and streak tracking.

Streaks are computed from daily reading session totals. A streak continues
while the reader has at least one session each calendar day; missing a full
day resets it.
"""

from collections import defaultdict
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.routes.auth import get_current_user
from app.core.models import Activity, ReadingProgress, ReadingSession, UserStats, User
from app.db.database import get_db

router = APIRouter()


def _get_or_create_stats(db: Session, user_id: str) -> UserStats:
    stats = db.query(UserStats).filter(UserStats.user_id == user_id).first()
    if not stats:
        stats = UserStats(user_id=user_id)
        db.add(stats)
        db.commit()
        db.refresh(stats)
    return stats


def _completed_book_count(db: Session, user_id: str) -> int:
    """Number of distinct books the user has read to ~100% (matches the UI's
    rounded 100% display)."""
    return (
        db.query(ReadingProgress)
        .filter(ReadingProgress.user_id == user_id, ReadingProgress.current_page >= 99.5)
        .count()
    )


def _compute_streaks(session_dates: list[date]) -> tuple[int, int]:
    """Return (current_streak, best_streak) from a list of distinct read dates."""
    if not session_dates:
        return 0, 0

    days = sorted(session_dates)
    current = 0
    best = 0
    run = 0
    prev: date | None = None

    for day in days:
        if prev is None:
            run = 1
        elif (day - prev).days == 1:
            run += 1
        elif (day - prev).days > 1:
            run = 1
        prev = day
        best = max(best, run)

    # Only count a streak as "current" if the most recent read was today or
    # yesterday; otherwise the current streak is considered broken.
    today = datetime.now(timezone.utc).date()
    if days[-1] == today or (today - days[-1]).days == 1:
        current = run
    else:
        current = 0

    return current, best


class SessionReport(BaseModel):
    book_id: str | None = None
    pages: int = Field(default=0, ge=0)
    minutes: int = Field(default=0, ge=0)
    finished: bool = False


@router.post("/sessions")
def record_session(body: SessionReport, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user_id = user.id
    session = ReadingSession(
        book_id=body.book_id,
        pages=body.pages,
        minutes=body.minutes,
    )
    db.add(session)

    stats = _get_or_create_stats(db, user_id)
    stats.total_pages += body.pages
    stats.total_reading_minutes += body.minutes
    if body.finished:
        already = (
            db.query(Activity)
            .filter(
                Activity.user_id == user_id,
                Activity.book_id == body.book_id,
                Activity.kind == "finished",
            )
            .first()
        )
        if not already:
            stats.books_completed += 1
            db.add(Activity(user_id=user_id, kind="finished", book_id=body.book_id))
    stats.books_completed = max(stats.books_completed, _completed_book_count(db, user_id))

    # Recompute streaks from all recorded sessions.
    rows = db.query(ReadingSession).filter(ReadingSession.user_id == user_id).all()
    dates = [r.started_at.date() for r in rows]
    stats.current_streak, stats.best_streak = _compute_streaks(dates)
    stats.last_read_date = datetime.utcnow()
    db.commit()

    return {
        "current_streak": stats.current_streak,
        "best_streak": stats.best_streak,
        "books_completed": stats.books_completed,
    }


@router.get("/")
def get_stats(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    stats = _get_or_create_stats(db, user.id)
    return {
        "books_completed": max(stats.books_completed, _completed_book_count(db, user.id)),
        "total_pages": stats.total_pages,
        "total_reading_minutes": stats.total_reading_minutes,
        "current_streak": stats.current_streak,
        "best_streak": stats.best_streak,
        "last_read_date": stats.last_read_date,
    }


@router.get("/monthly")
def get_monthly_progress(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Return reading minutes grouped by month for the trailing 6 months."""
    rows = db.query(ReadingSession).filter(ReadingSession.user_id == user.id).all()

    by_month: dict[str, int] = defaultdict(int)
    for r in rows:
        key = r.started_at.strftime("%Y-%m")
        by_month[key] += r.minutes

    # Ensure all of the last 6 months are present, even with zero minutes.
    today = datetime.now(timezone.utc)
    months: list[dict] = []
    for offset in range(5, -1, -1):
        year_month = today.year, today.month - offset
        year, month = year_month[0], ((year_month[1] - 1) % 12) + 1
        if year_month[1] < 1:
            year -= 1
        key = f"{year:04d}-{month:02d}"
        months.append({"month": key, "label": datetime(year, month, 1).strftime("%b"), "minutes": by_month[key]})

    return months
