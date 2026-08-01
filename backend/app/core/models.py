import uuid
from datetime import datetime

from sqlalchemy import Column, String, DateTime, Float, ForeignKey, Boolean, Text, Enum, Integer, Table
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.database import Base


def gen_uuid():
    return str(uuid.uuid4())


# Many-to-many association: which books live on which shelves.
shelf_books = Table(
    "shelf_books",
    Base.metadata,
    Column("shelf_id", UUID(as_uuid=False), ForeignKey("shelves.id"), primary_key=True),
    Column("book_id", UUID(as_uuid=False), ForeignKey("books.id"), primary_key=True),
)


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    email = Column(String, unique=True, nullable=False, index=True)
    hashed_password = Column(String, nullable=False)
    display_name = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Email verification
    is_verified = Column(Boolean, default=False)
    verification_token = Column(String, nullable=True)
    verification_token_expires = Column(DateTime, nullable=True)

    # Password reset
    reset_token = Column(String, nullable=True)
    reset_token_expires = Column(DateTime, nullable=True)

    # Profile banner (object-storage key, shown on the Shelves page hero)
    banner_key = Column(String, nullable=True)

    books = relationship("Book", back_populates="owner")
    shelves = relationship("Shelf", back_populates="owner", cascade="all, delete-orphan")
    settings = relationship(
        "UserSettings", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    stats = relationship(
        "UserStats", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    following = relationship(
        "Follow",
        foreign_keys="Follow.follower_id",
        back_populates="follower",
        cascade="all, delete-orphan",
    )


class Book(Base):
    __tablename__ = "books"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    owner_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    title = Column(String, nullable=False)
    author = Column(String, nullable=True)
    genre = Column(String, nullable=True)
    original_filename = Column(String, nullable=False)
    storage_key = Column(String, nullable=False)  # path in object storage for original PDF
    structured_text_key = Column(String, nullable=True)  # path to reflow-ready extracted JSON
    cover_key = Column(String, nullable=True)  # object-storage key of the book cover image

    # Extraction metadata
    extraction_status = Column(
        Enum("pending", "processing", "done", "failed", name="extraction_status"),
        default="pending",
    )
    reflow_confidence = Column(Float, nullable=True)  # 0.0-1.0, see structure.py
    is_scanned = Column(Boolean, default=False)
    page_count = Column(Float, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="books")


class ReadingProgress(Base):
    __tablename__ = "reading_progress"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    book_id = Column(UUID(as_uuid=False), ForeignKey("books.id"), nullable=False)
    current_page = Column(Float, default=0)
    current_offset = Column(Float, default=0)  # scroll/char offset within reflowed text
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class Annotation(Base):
    __tablename__ = "annotations"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    book_id = Column(UUID(as_uuid=False), ForeignKey("books.id"), nullable=False)
    kind = Column(Enum("highlight", "note", "bookmark", name="annotation_kind"))
    anchor = Column(Text)  # serialized position (page + char range, or reflow offset)
    color = Column(String, nullable=True)
    note_text = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class Shelf(Base):
    __tablename__ = "shelves"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    owner_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    color = Column(String, nullable=True)  # hex accent color for the collection
    banner_key = Column(String, nullable=True)  # object-storage key of the banner image
    is_public = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="shelves")
    books = relationship("Book", secondary=shelf_books)


class ShelfFollow(Base):
    __tablename__ = "shelf_follows"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    shelf_id = Column(UUID(as_uuid=False), ForeignKey("shelves.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class UserSettings(Base):
    """Per-user reading preferences, matching the Reading Settings panel."""

    __tablename__ = "user_settings"

    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), primary_key=True)
    theme = Column(String, default="sepia")  # light | dark | sepia | night | mint | rose
    custom_background = Column(String, nullable=True)  # hex, e.g. #f4ecd8
    font_family = Column(String, default="serif")  # serif | sans | dyslexic
    font_size = Column(Integer, default=20)
    line_spacing = Column(Float, default=1.6)
    margins = Column(String, default="medium")  # small | medium | large
    reading_mode = Column(String, default="scroll")  # scroll | paginate
    page_layout = Column(String, default="spread")  # spread (two-page) | single (one-page)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="settings")


class UserStats(Base):
    """Aggregated reading stats shown on the Profile & Stats page."""

    __tablename__ = "user_stats"

    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), primary_key=True)
    books_completed = Column(Integer, default=0)
    total_pages = Column(Integer, default=0)
    total_reading_minutes = Column(Integer, default=0)
    current_streak = Column(Integer, default=0)
    best_streak = Column(Integer, default=0)
    last_read_date = Column(DateTime, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="stats")


class ReadingSession(Base):
    """A single reading session, the raw material for stats & streaks."""

    __tablename__ = "reading_sessions"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    book_id = Column(UUID(as_uuid=False), ForeignKey("books.id"), nullable=True)
    pages = Column(Integer, default=0)
    minutes = Column(Integer, default=0)
    started_at = Column(DateTime, default=datetime.utcnow)


class Follow(Base):
    __tablename__ = "follows"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    follower_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    following_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    follower = relationship("User", foreign_keys=[follower_id], back_populates="following")


class Activity(Base):
    """Community feed events: finished a book, highlighted, shared a shelf."""

    __tablename__ = "activity"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    kind = Column(
        Enum("finished", "highlighted", "shelf_shared", "reviewed", name="activity_kind")
    )
    book_id = Column(UUID(as_uuid=False), ForeignKey("books.id"), nullable=True)
    shelf_id = Column(UUID(as_uuid=False), ForeignKey("shelves.id"), nullable=True)
    text = Column(Text, nullable=True)  # e.g. review snippet or note
    created_at = Column(DateTime, default=datetime.utcnow)
