import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import books, auth, sync, shelves, settings as settings_routes, stats, social
from app.config import settings

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

app = FastAPI(title=settings.app_name)

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
