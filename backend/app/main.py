import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import books, auth, sync, shelves, settings as settings_routes, stats, social
from app.config import settings
from app.db.database import SessionLocal

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

logger = logging.getLogger("cloudread.main")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """On startup, un-stick any extraction that died with the last process.

    Render free-tier instances can be recycled mid-job, which leaves a book
    stuck at ``processing`` forever (and ``re-extract`` refuses it with 409).
    Reset those to ``failed`` so the client stops polling and the user can
    retry.
    """
    from app.core.models import Book

    db = SessionLocal()
    try:
        stuck = db.query(Book).filter(Book.extraction_status == "processing").all()
        for book in stuck:
            book.extraction_status = "failed"
            logger.info("Reset book %s stuck at 'processing' to 'failed'", book.id)
        if stuck:
            db.commit()
    except Exception:
        logger.exception("Could not reset stuck extractions on startup")
    finally:
        db.close()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(books.router, prefix="/books", tags=["books"])
app.include_router(sync.router, prefix="/sync", tags=["sync"])
app.include_router(shelves.router, prefix="/shelves", tags=["shelves"])
app.include_router(settings_routes.router, prefix="/settings", tags=["settings"])
app.include_router(stats.router, prefix="/stats", tags=["stats"])
app.include_router(social.router, prefix="/social", tags=["social"])


@app.api_route("/health", methods=["GET", "HEAD"])
def health_check():
    return {"status": "ok", "app": settings.app_name}
