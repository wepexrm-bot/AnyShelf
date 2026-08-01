"""Orchestrates the full extraction pipeline end to end:

upload -> extract spans -> (OCR fallback if scanned) -> reading order ->
paragraph/heading reconstruction -> confidence score -> structured JSON

This is the module the background job (triggered on upload) calls.
"""

import json

from app.config import settings


def run_pipeline(pdf_path: str, progress_cb=None) -> dict:
    """Run the full extraction pipeline.

    ``progress_cb`` (if given) is called with a fraction (0.0-1.0) at each
    stage so callers can surface live 0-100% progress to the user.
    """

    import fitz

    from app.core.extraction.extractor import extract_spans, get_pdf_outline
    from app.core.extraction.ocr import ocr_page
    from app.core.extraction.reading_order import order_reading_sequence
    from app.core.extraction.structure import (
        filter_running_noise,
        group_into_lines,
        Line,
        reconstruct_blocks_from_lines,
        score_reflow_confidence,
        StructuredPage,
    )

    def report(fraction: float):
        if progress_cb:
            progress_cb(fraction)

    doc = fitz.open(pdf_path)
    page_widths = [page.rect.width for page in doc]
    page_heights = [page.rect.height for page in doc]
    doc.close()
    report(0.05)

    total_pages = max(len(page_widths), 1)

    pages = extract_spans(pdf_path, progress_cb=lambda f: report(0.05 + 0.20 * f))
    outline = get_pdf_outline(pdf_path)
    report(0.28)

    # Group spans into lines per page first, so we can drop running
    # headers/footers and page numbers (repeated noise) before reconstructing
    # paragraphs.
    lines_by_page: list[list[Line]] = []
    scanned_page_count = 0

    for page in pages:
        spans = page.spans

        if not page.has_text_layer:
            scanned_page_count += 1
            ocr_spans, ocr_confidence = ocr_page(pdf_path, page.page_number)
            spans = ocr_spans
            if ocr_confidence < settings.ocr_confidence_threshold:
                # Very low-confidence OCR: still record what we found, but
                # this page will drag the overall reflow score down below.
                pass

        ordered = order_reading_sequence(spans, page_widths[page.page_number])
        lines_by_page.append(group_into_lines(ordered))
        report(0.30 + 0.62 * ((page.page_number + 1) / total_pages))

    lines_by_page = filter_running_noise(lines_by_page, page_heights)
    report(0.94)

    structured_pages: list[StructuredPage] = []
    for page, lines in zip(pages, lines_by_page):
        blocks = reconstruct_blocks_from_lines(lines)
        structured_pages.append(StructuredPage(page_number=page.page_number, blocks=blocks))

    scanned_ratio = scanned_page_count / len(pages) if pages else 0.0
    confidence = score_reflow_confidence(structured_pages, scanned_ratio, outline=outline)
    report(0.98)

    result = {
        "outline": outline,
        "reflow_confidence": confidence,
        "is_scanned": scanned_ratio > 0.5,
        "reflow_mode_recommended": confidence >= 0.5,
        "pages": [
            {
                "page_number": p.page_number,
                "blocks": [{"kind": b.kind, "text": b.text, "level": b.level} for b in p.blocks],
            }
            for p in structured_pages
        ],
    }
    return result


def run_pipeline_to_json(pdf_path: str) -> str:
    return json.dumps(run_pipeline(pdf_path), indent=2)
