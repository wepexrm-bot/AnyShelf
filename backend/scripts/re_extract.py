"""One-time maintenance script: re-extract every book into the new text-layer
format (``textlayer-v1``).

Books uploaded before the text-layer engine replaced the reflow pipeline store
old reflow-block JSON under ``structured_text_key``. This script downloads each
book's original PDF from object storage, re-runs the extraction pipeline, and
rewrites the stored JSON plus the book's confidence/is_scanned/page_count
columns. It is idempotent and safe to re-run.

Usage (from backend/):
    venv\\Scripts\\python -m scripts.re_extract
"""

import json
import logging
import os
import tempfile
import uuid

from app.core.models import Book
from app.core.storage import download_bytes, upload_bytes
from app.core.extraction.pipeline import run_pipeline
from app.db.database import SessionLocal

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("cloudread.re_extract")


def main():
    db = SessionLocal()
    books = db.query(Book).filter(Book.structured_text_key.isnot(None)).order_by(Book.created_at.asc()).all()
    logger.info("Found %d books with extraction data to re-extract", len(books))

    ok = failed = 0
    try:
        for book in books:
            try:
                pdf_bytes = download_bytes(book.storage_key)
                with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
                    tmp.write(pdf_bytes)
                    tmp_path = tmp.name
                try:
                    def upload_page_image(data: bytes, ext: str) -> str:
                        key = f"images/{book.owner_id}/{book.id}/{uuid.uuid4().hex}.{ext}"
                        upload_bytes(data, storage_key=key, content_type="image/jpeg" if ext == "jpg" else "image/png")
                        return key

                    result = run_pipeline(tmp_path, image_uploader=upload_page_image)
                finally:
                    try:
                        os.remove(tmp_path)
                    except OSError:
                        pass

                structured_key = f"structured/{book.owner_id}/{book.id}.json"
                upload_bytes(
                    data=json.dumps(result).encode("utf-8"),
                    storage_key=structured_key,
                    content_type="application/json",
                )

                book.structured_text_key = structured_key
                book.reflow_confidence = result["text_confidence"]
                book.is_scanned = result["is_scanned"]
                book.page_count = len(result["pages"])
                book.extraction_status = "done"
                db.commit()
                logger.info("Re-extracted %s (%s): %d pages, coverage %s", book.id, book.title, book.page_count, book.reflow_confidence)
                ok += 1
            except Exception as exc:
                logger.exception("Re-extract failed for book %s (%s): %s", book.id, book.title, exc)
                try:
                    db.rollback()
                except Exception:
                    pass
                failed += 1
    finally:
        db.close()

    logger.info("Done: %d succeeded, %d failed", ok, failed)
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
