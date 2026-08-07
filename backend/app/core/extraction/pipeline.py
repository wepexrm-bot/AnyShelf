"""Orchestrates the text-layer extraction pipeline end to end:

upload -> extract positioned runs -> (OCR fallback if scanned) ->
assemble text-layer JSON + outline + coverage + native annotation anchors

This is the module the background job (triggered on upload) calls.
The output schema (``textlayer-v1``) mirrors pdf.js ``getTextContent()`` text
items so clients can render the PDF's native text layer faithfully.
"""

import json
import logging
import time

import fitz

from app.config import settings

logger = logging.getLogger("cloudread.pipeline")


def run_pipeline(pdf_path: str, progress_cb=None) -> dict:
    """Run the full text-layer pipeline.

    ``progress_cb`` (if given) is called with a fraction (0.0-1.0) at each
    stage so callers can surface live 0-100% progress to the user.
    """

    from app.core.extraction.extractor import extract_text_runs, get_pdf_outline
    from app.core.extraction.ocr import ocr_page
    from app.core.extraction.coverage import text_coverage
    from app.core.extraction.annotations import reconcile_native_annotations

    started = time.perf_counter()

    def report(fraction: float):
        if progress_cb:
            progress_cb(fraction)

    def stage_done(stage: str, since: float) -> float:
        now = time.perf_counter()
        logger.info("pipeline %s: %.2fs (total %.2fs)", stage, now - since, now - started)
        return now

    t = time.perf_counter()
    report(0.05)

    doc = fitz.open(pdf_path)
    try:
        pages = extract_text_runs(pdf_path, progress_cb=lambda f: report(0.05 + 0.20 * f), doc=doc)
        t = stage_done("text_runs", t)
        outline = get_pdf_outline(pdf_path, doc=doc)
        t = stage_done("outline", t)
        report(0.28)

        total_pages = max(len(pages), 1)
        pages_with_text = 0

        for page_index, page in enumerate(pages):
            page.has_image = bool(doc.load_page(page_index).get_image_info())
            if not page.has_text_layer:
                ocr_runs, ocr_confidence = ocr_page(pdf_path, page_index, doc=doc)
                if ocr_confidence >= settings.ocr_confidence_threshold and ocr_runs:
                    page.runs = ocr_runs
                else:
                    # Low-confidence OCR or no text at all: keep the page blank so
                    # it drags the coverage score down (and can fall back to the
                    # raster PDF viewer when coverage is very low).
                    page.runs = []
            if page.runs:
                pages_with_text += 1
            report(0.30 + 0.62 * ((page_index + 1) / total_pages))

        t = stage_done("ocr_fallback", t)

        report(0.94)
        coverage = text_coverage(pages_with_text, total_pages)
        imported_annotations = reconcile_native_annotations(pages)
        t = stage_done("annotations", t)
        report(0.98)

        result = {
            "schema": "textlayer-v1",
            "outline": outline,
            "text_confidence": coverage,
            "is_scanned": coverage < 0.5,
            "imported_annotations": imported_annotations,
            "pages": [
                {
                    "page": p.page_index,
                    "width": round(p.width, 2),
                    "height": round(p.height, 2),
                    "rotation": p.rotation,
                    "has_image": p.has_image,
                    "runs": [
                        {
                            "t": r.text,
                            "x": round(r.x, 2),
                            "y": round(r.y, 2),
                            "fs": round(r.font_size, 2),
                            "w": round(r.advance, 2),
                            "f": r.font,
                            "flags": r.flags,
                        }
                        for r in p.runs
                    ],
                }
                for p in pages
            ],
        }
    finally:
        doc.close()

    logger.info(
        "pipeline complete: %d pages, %d runs, coverage=%.2f, total %.2fs",
        len(pages),
        sum(len(p.runs) for p in pages),
        coverage,
        time.perf_counter() - started,
    )
    return result


def run_pipeline_to_json(pdf_path: str) -> str:
    return json.dumps(run_pipeline(pdf_path), indent=2)
