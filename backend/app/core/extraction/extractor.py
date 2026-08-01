"""Step 1 of the pipeline: layout-aware extraction of text spans from a PDF.

Instead of a flat text dump, this pulls out each span of text along with its
bounding box, font, and size -- the raw material needed to reconstruct
reading order and paragraph/heading structure later in the pipeline.
"""

from dataclasses import dataclass

import fitz  # PyMuPDF


@dataclass
class TextSpan:
    text: str
    x0: float
    y0: float
    x1: float
    y1: float
    font: str
    size: float
    page_number: int


@dataclass
class PageExtraction:
    page_number: int
    spans: list[TextSpan]
    has_text_layer: bool  # False => likely a scanned/image-only page, needs OCR


def extract_spans(pdf_path: str, progress_cb=None) -> list[PageExtraction]:
    """Extract raw text spans with layout info from every page of a PDF.

    ``progress_cb`` (if given) is called after each page with a fraction
    (0.0-1.0) of the document completed, so callers can report live progress.
    """
    doc = fitz.open(pdf_path)
    pages: list[PageExtraction] = []
    total = doc.page_count

    for page_index, page in enumerate(doc):
        raw = page.get_text("dict")
        spans: list[TextSpan] = []

        for block in raw.get("blocks", []):
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    text = span.get("text", "").strip()
                    if not text:
                        continue
                    x0, y0, x1, y1 = span["bbox"]
                    spans.append(
                        TextSpan(
                            text=text,
                            x0=x0,
                            y0=y0,
                            x1=x1,
                            y1=y1,
                            font=span.get("font", ""),
                            size=span.get("size", 0.0),
                            page_number=page_index,
                        )
                    )

        # If a page has (almost) no extractable text, it's very likely a
        # scanned image with no embedded text layer -- flag it for OCR.
        # Use character count, not span count: Word-exported PDFs can pack a
        # full page into a handful of long spans, so span count alone would
        # wrongly route text pages to OCR.
        total_chars = sum(len(s.text) for s in spans)
        has_text_layer = total_chars > 15

        pages.append(
            PageExtraction(page_number=page_index, spans=spans, has_text_layer=has_text_layer)
        )

        if progress_cb:
            progress_cb((page_index + 1) / total)

    doc.close()
    return pages


def get_pdf_outline(pdf_path: str) -> list[dict]:
    """Pull the PDF's built-in bookmarks/outline, if present -- a free,
    reliable source of chapter/heading structure when available."""
    doc = fitz.open(pdf_path)
    toc = doc.get_toc()  # [[level, title, page_number], ...]
    doc.close()
    return [{"level": lvl, "title": title, "page": page} for lvl, title, page in toc]
