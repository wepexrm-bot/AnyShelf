"""OCR fallback for pages with no embedded text layer (scanned PDFs).

Produces output in the same TextSpan shape as extractor.py so it can feed
into the same reading-order/structure reconstruction steps downstream.
"""

import io
import logging

import fitz
import pytesseract
from PIL import Image

from app.core.extraction.extractor import TextSpan
from app.config import settings

logger = logging.getLogger("cloudread.ocr")


def render_page_to_image(pdf_path: str, page_number: int, dpi: int = 300) -> Image.Image:
    doc = fitz.open(pdf_path)
    page = doc[page_number]
    zoom = dpi / 72
    pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom))
    img = Image.open(io.BytesIO(pix.tobytes("png")))
    doc.close()
    return img


def ocr_page(pdf_path: str, page_number: int) -> tuple[list[TextSpan], float]:
    """Run OCR on a single page. Returns (spans, avg_confidence 0-1)."""
    image = render_page_to_image(pdf_path, page_number)

    if settings.use_cloud_ocr:
        # Placeholder: swap in Google Cloud Vision / AWS Textract here for
        # better accuracy on difficult scans. Left as local Tesseract by
        # default to keep the stack simple and free to run.
        raise NotImplementedError("Wire up a cloud OCR provider here")

    try:
        data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT)
    except Exception as exc:
        # Tesseract not installed / not on PATH. Don't fail the whole book:
        # pages without a text layer just contribute no OCR content instead
        # of crashing extraction (a single image cover shouldn't kill a
        # otherwise text-based PDF).
        logger.warning("OCR unavailable (book=%s page=%s): %s", pdf_path, page_number, exc)
        return [], 0.0

    spans: list[TextSpan] = []
    confidences: list[float] = []

    for i, text in enumerate(data["text"]):
        text = text.strip()
        if not text:
            continue
        conf = float(data["conf"][i])
        if conf < 0:  # tesseract uses -1 for non-text regions
            continue
        confidences.append(conf)

        x, y, w, h = data["left"][i], data["top"][i], data["width"][i], data["height"][i]
        spans.append(
            TextSpan(
                text=text,
                x0=x,
                y0=y,
                x1=x + w,
                y1=y + h,
                font="ocr",
                size=float(h),
                page_number=page_number,
            )
        )

    avg_confidence = (sum(confidences) / len(confidences) / 100) if confidences else 0.0
    return spans, avg_confidence
