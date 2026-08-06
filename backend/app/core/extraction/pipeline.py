"""Orchestrates the text-layer extraction pipeline end to end:

upload -> extract positioned runs -> (OCR fallback if scanned) ->
assemble text-layer JSON + outline + coverage + native annotation anchors

This is the module the background job (triggered on upload) calls.
The output schema (``textlayer-v1``) mirrors pdf.js ``getTextContent()`` text
items so clients can render the PDF's native text layer faithfully.
"""

import json

from app.config import settings


def run_pipeline(pdf_path: str, progress_cb=None, image_uploader=None) -> dict:
    """Run the full text-layer pipeline.

    ``progress_cb`` (if given) is called with a fraction (0.0-1.0) at each
    stage so callers can surface live 0-100% progress to the user.

    ``image_uploader`` (if given) is a ``callable(data: bytes, ext: str) ->
    storage_key`` used to persist each page image to object storage. When
    absent, images are extracted but not persisted and pages carry an empty
    ``images`` list (used by tests / callers that only need text).
    """

    from app.core.extraction.extractor import extract_text_runs, get_pdf_outline
    from app.core.extraction.ocr import ocr_page
    from app.core.extraction.coverage import text_coverage
    from app.core.extraction.annotations import reconcile_native_annotations

    def report(fraction: float):
        if progress_cb:
            progress_cb(fraction)

    report(0.05)

    pages = extract_text_runs(pdf_path, progress_cb=lambda f: report(0.05 + 0.20 * f))
    outline = get_pdf_outline(pdf_path)
    report(0.28)

    total_pages = max(len(pages), 1)
    pages_with_text = 0

    for page_index, page in enumerate(pages):
        if not page.has_text_layer:
            ocr_runs, ocr_confidence = ocr_page(pdf_path, page_index)
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

    report(0.94)
    coverage = text_coverage(pages_with_text, total_pages)
    imported_annotations = reconcile_native_annotations(pages)
    report(0.98)

    result = {
        "schema": "textlayer-v1",
        "outline": outline,
        "text_confidence": coverage,
        "reflow_confidence": coverage,
        "is_scanned": coverage < 0.5,
        "reflow_mode_recommended": coverage >= 0.5,
        "imported_annotations": imported_annotations,
        "pages": [
            {
                "page": p.page_index,
                "width": round(p.width, 2),
                "height": round(p.height, 2),
                "rotation": p.rotation,
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
                "images": [
                    {
                        "x": round(img.x0, 2),
                        "y": round(img.y0, 2),
                        "w": round(img.x1 - img.x0, 2),
                        "h": round(img.y1 - img.y0, 2),
                        "key": image_uploader(img.data, img.ext) if image_uploader else None,
                    }
                    for img in p.images
                ],
            }
            for p in pages
        ],
    }
    return result


def run_pipeline_to_json(pdf_path: str) -> str:
    return json.dumps(run_pipeline(pdf_path), indent=2)
