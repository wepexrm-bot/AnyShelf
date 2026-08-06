"""Step 4a of the pipeline (optional): import native PDF annotations.

A highlight or margin note in the PDF lives at a fixed rectangle on a fixed
page. The text layer keeps the same coordinates, so we anchor imported
annotations by *character range* within the page's reading-order run stream:

1. Each run already carries its baseline, font height and advance width, so we
   can reconstruct its bounding box and test overlap against the annotation
   rectangle.
2. Runs are in reading order; the annotation's char range is the span from the
   first overlapped run's start to the last overlapped run's end.
3. We also keep the matched text plus a few words of surrounding context, so
   annotations survive re-extraction and can be found by text search too (a
   fallback the mobile/web readers use for older, text-anchored rows).

The result is a list of dicts describing imported annotations; the caller
persists them (see app.api.routes.books.process_extraction) keyed to the book
owner.
"""

from typing import Iterable

from app.core.extraction.extractor import NativeAnnotation, PageExtraction, TextRun

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


def reconcile_native_annotations(pages: Iterable[PageExtraction]) -> list[dict]:
    """Turn each page's raw annotation rectangles into char-anchored dicts.

    Runs are consumed in reading order (the order they were extracted, which
    rawdict already produces). Returns a list of dicts for the caller to
    persist:

        {"kind", "color", "note", "text", "page", "anchor"}
    where ``anchor`` is
        {"page","start_char","end_char","text","context_before","context_after"}.
    """
    result: list[dict] = []
    for page in pages:
        for annot in page.native_annotations:
            result.append(_reconcile_one(annot, page))
    return result


def _run_bbox(run: TextRun) -> tuple[float, float, float, float]:
    return run.x, run.y - run.font_size, run.x + max(run.advance, 0.0), run.y


def _overlaps(run: TextRun, annot: NativeAnnotation) -> bool:
    # Small tolerance so a tight highlight that barely grazes a glyph still
    # counts as covering that run.
    tol = 1.0
    x0, y0, x1, y1 = _run_bbox(run)
    return not (
        x1 < annot.x0 - tol
        or x0 > annot.x1 + tol
        or y1 < annot.y0 - tol
        or y0 > annot.y1 + tol
    )


def _char_offsets(runs: list[TextRun]) -> list[tuple[int, int]]:
    """Global char offsets (start, end) of each run within the page's stream."""
    offsets: list[tuple[int, int]] = []
    acc = 0
    for r in runs:
        offsets.append((acc, acc + len(r.text)))
        acc += len(r.text)
    return offsets


def _reconcile_one(annot: NativeAnnotation, page: PageExtraction) -> dict:
    runs = page.runs
    offsets = _char_offsets(runs)
    overlaps: list[int] = []
    for i, r in enumerate(runs):
        if _overlaps(r, annot):
            overlaps.append(i)

    matched_parts: list[str] = []
    context_before = ""
    context_after = ""

    if overlaps:
        start, end = overlaps[0], overlaps[-1]
        matched_parts = [runs[i].text.strip() for i in range(start, end + 1) if runs[i].text.strip()]

        before_runs = [runs[i].text.strip() for i in range(max(0, start - _CONTEXT_SPAN_WINDOW), start) if runs[i].text.strip()]
        context_before = _clip_context(" ".join(before_runs))

        after_runs = [runs[i].text.strip() for i in range(end + 1, min(len(runs), end + 1 + _CONTEXT_SPAN_WINDOW)) if runs[i].text.strip()]
        context_after = _clip_context(" ".join(after_runs))

    start_char = offsets[start][0] if overlaps else None
    end_char = offsets[end][1] if overlaps else None
    text = " ".join(matched_parts)

    return {
        "kind": annot.kind,
        "color": _rgb_color(annot.color),
        "note": annot.note_text,
        "text": text,
        "page": page.page_index,
        "anchor": {
            "page": page.page_index,
            "start_char": start_char,
            "end_char": end_char,
            "text": text,
            "context_before": context_before,
            "context_after": context_after,
        },
    }
