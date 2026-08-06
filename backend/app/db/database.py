from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base

from app.config import settings

engine = create_engine(
    settings.database_url,
    # Render closes idle Postgres connections; ping each pooled connection
    # before use so a dropped one is replaced instead of failing a request.
    pool_pre_ping=True,
    pool_recycle=300,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Columns added after a table already exists in the DB. ``create_all`` only
# creates missing tables, never alters existing ones, so these are applied as
# idempotent ALTERs on every boot (each guarded by IF NOT EXISTS).
_MIGRATIONS = [
    "ALTER TABLE books ADD COLUMN IF NOT EXISTS extraction_progress INTEGER DEFAULT 0",
]


def run_migrations() -> None:
    """Apply idempotent schema migrations for existing tables."""
    with engine.begin() as conn:
        for statement in _MIGRATIONS:
            conn.execute(text(statement))


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
