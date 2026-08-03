"""Step 4a of the pipeline (optional): import native PDF annotations.

A highlight or margin note in the PDF lives at a fixed rectangle on a fixed
page. Reflow abandons fixed coordinates, so we bridge the two worlds here:

1. Two-up spread pages get split into logical pages in extractor.extract_spans;
   each logical page already carries the raw annotation rectangles that fall
   on it (NativeAnnotation).
2. For each annotation we find which TextSpans its rectangle overlaps -- that
   overlap is the highlighted text itself, found via layout, in reading order.
3. We anchor the annotation by *text content*, not coordinates: the matched
   text plus a few words of surrounding context. Substring-searching that text
   inside the reflowed paragraphs later locates it regardless of pagination,
   font size, or re-extraction shifting character offsets.

The result is a list of dicts describing imported annotations; the caller
persists them (see app.api.routes.books.process_extraction) keyed to the book
owner.
"""

from typing import Iterable

from app.core.extraction.extractor import NativeAnnotation, PageExtraction, TextSpan

# Reading-order window for context, and the max length kept so repeated phrases
# get disambiguated without storing the whole page.
_CONTEXT_SPAN_WINDOW = 6
_CONTEXT_MAX_CHARS = 120


def _rgb_color(rgb: tuple | None, default: str = "#FFD54F") -> str:
    """Convert a PyMuPDF (r, g, b) 0.0-1.0 stroke tuple to a hex string."""
    if not rgb:
        return default
    try:
        return "#{:02X}{:02X}{:02X}".format(
            *(max(0, min(255, int(round(c * 255)))) for c in rgb[:3])
        )
    except (TypeError, ValueError):
        return default


def _clip_context(text: str) -> str:
    return text.strip()[-_CONTEXT_MAX_CHARS:]


def reconcile_native_annotations(
    pages: Iterable[PageExtraction],
    ordered_spans_by_page=None,
) -> list[dict]:
    """Turn each page's raw annotation rectangles into text-anchored dicts.

    ``ordered_spans_by_page`` (optional) lets the caller supply the per-page
    reading-order span sequence; when omitted we sort each page's spans by
    (y, x) ourselves (a close enough approximation for context windows).

    Returns a list of dicts for the caller to persist:
        {"kind", "color", "note", "text", "page", "anchor"}
    where ``anchor`` is {"text","context_before","context_after","page"}.
    """
    result: list[dict] = []
    for page in pages:
        spans: list[TextSpan] = (
            ordered_spans_by_page.get(page.page_number, [])
            if ordered_spans_by_page
            else sorted(page.spans, key=lambda s: (s.y0, s.x0))
        )
        for annot in page.native_annotations:
            result.append(_reconcile_one(annot, spans, page.page_number))
    return result


def _overlaps(span: TextSpan, annot: NativeAnnotation) -> bool:
    # Small tolerance so a tight highlight that barely grazes a glyph still
    # counts as covering that span.
    tol = 1.0
    return not (
        span.x1 < annot.x0 - tol
        or span.x0 > annot.x1 + tol
        or span.y1 < annot.y0 - tol
        or span.y0 > annot.y1 + tol
    )


def _reconcile_one(
    annot: NativeAnnotation, spans: list[TextSpan], page_number: int
) -> dict:
    # Spans arrive in reading order. Find the contiguous run overlapping the
    # rectangle, plus the run just before (context_before) and after.
    overlaps: list[int] = []
    for i, s in enumerate(spans):
        if _overlaps(s, annot):
            overlaps.append(i)

    matched_parts: list[str] = []
    context_before = ""
    context_after = ""

    if overlaps:
        start, end = overlaps[0], overlaps[-1]
        matched_parts = [s.text.strip() for s in spans[start : end + 1] if s.text.strip()]

        before_spans = [
            s.text.strip()
            for s in spans[max(0, start - _CONTEXT_SPAN_WINDOW) : start]
            if s.text.strip()
        ]
        context_before = _clip_context(" ".join(before_spans))

        after_spans = [
            s.text.strip()
            for s in spans[end + 1 : end + 1 + _CONTEXT_SPAN_WINDOW]
            if s.text.strip()
        ]
        context_after = _clip_context(" ".join(after_spans))

    text = " ".join(matched_parts)

    return {
        "kind": annot.kind,
        "color": _rgb_color(annot.color),
        "note": annot.note_text,
        "text": text,
        "page": page_number,
        "anchor": {
            "text": text,
            "context_before": context_before,
            "context_after": context_after,
            "page": page_number,
        },
    }