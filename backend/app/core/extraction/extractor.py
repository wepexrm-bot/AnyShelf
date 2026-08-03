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
    page_number: int  # logical page index, sequential from 0 after any splits
    spans: list[TextSpan]
    has_text_layer: bool  # False => likely a scanned/image-only page, needs OCR
    page_width: float = 0.0
    page_height: float = 0.0
    pdf_page_index: int = 0  # original physical page index into the PDF
    # Native PDF annotations (highlights, underlines, margin notes) found on
    # this logical page. Coordinates are still in physical-page space, so they
    # can be reconciled against `spans` (which keep their original coords even
    # after a two-up split).
    native_annotations: list["NativeAnnotation"] = None

    def __post_init__(self):
        for s in self.spans:
            s.page_number = self.page_number
        if self.native_annotations is None:
            self.native_annotations = []


@dataclass
class NativeAnnotation:
    """A raw annotation rectangle pulled straight from the PDF, before it is
    mapped to the text it covers. Kind is PyMuPDF's annotation type name."""

    x0: float
    y0: float
    x1: float
    y1: float
    kind: str = "highlight"
    color: tuple | None = None  # (r, g, b) 0.0-1.0 stroke color
    note_text: str | None = None


# Two-up ("spread") PDFs lay two book pages side by side on one sheet. These
# constants tune the detector: a page is treated as two-up when both halves
# hold enough text and few spans straddle the vertical center line.
_TWO_UP_GUTTER_BAND = 25.0  # half-width of the center band, in points
_TWO_UP_MIN_SPANS_PER_HALF = 8
_TWO_UP_MAX_GUTTER_FRACTION = 0.45


# Horizontal gap (points) that breaks a visual line into separate clusters.
# Word spaces in body text are ~3-11pt while the gutter between the two
# columns of a two-up spread is ~19-21pt, so 12 separates them reliably.
_TWO_UP_COLUMN_GAP = 12.0


def _split_into_lines(spans: list[TextSpan]) -> list[list[TextSpan]]:
    """Group spans into visual lines by vertical band (tolerating the small
    baseline jitter PDFs introduce between spans on the same line) AND by
    horizontal adjacency, so the two columns of a two-up spread that happen
    to share a baseline never merge into one line."""
    if not spans:
        return []

    from statistics import median

    body_size = median(s.size for s in spans) if spans else 12.0
    tolerance = max(2.0, body_size * 0.55)

    ordered = sorted(spans, key=lambda s: (s.y0, s.x0))
    lines: list[list[TextSpan]] = []
    for span in ordered:
        for line in lines:
            baseline = sum(s.y0 for s in line) / len(line)
            if abs(span.y0 - baseline) < tolerance:
                line_min = min(s.x0 for s in line)
                line_max = max(s.x1 for s in line)
                if span.x1 < line_min - _TWO_UP_COLUMN_GAP or span.x0 > line_max + _TWO_UP_COLUMN_GAP:
                    continue  # same baseline but a different column / cluster
                line.append(span)
                break
        else:
            lines.append([span])
    return lines


def _split_two_up_spans(spans: list[TextSpan], page_width: float) -> list[list[TextSpan]] | None:
    """If a page carries two book pages side by side, return the spans split
    into ``[left_half, right_half]``; otherwise return ``None``.

    Each half is a full-height column, so spans whose horizontal center falls
    cleanly on one side belong there. Spans straddling the center line are
    handed to whichever column has text at a similar vertical position,
    preferring the left on a tie so chapter openers keep their headings.

    Whole lines that span the center line (spread-wide book titles and chapter
    heads, which PDFs fragment into many small spans) are kept intact and
    assigned as a unit, so a title never breaks across the two halves.
    """
    if not spans or page_width <= 0:
        return None

    mid = page_width / 2.0
    left_hint: list[TextSpan] = []
    right_hint: list[TextSpan] = []
    gutter: list[TextSpan] = []

    for s in spans:
        center = (s.x0 + s.x1) / 2.0
        if center < mid - _TWO_UP_GUTTER_BAND:
            left_hint.append(s)
        elif center > mid + _TWO_UP_GUTTER_BAND:
            right_hint.append(s)
        else:
            gutter.append(s)

    if len(left_hint) < _TWO_UP_MIN_SPANS_PER_HALF or len(right_hint) < _TWO_UP_MIN_SPANS_PER_HALF:
        return None
    if len(gutter) / len(spans) >= _TWO_UP_MAX_GUTTER_FRACTION:
        return None

    def overlap_count(column: list[TextSpan], line: list[TextSpan]) -> int:
        y0 = min(s.y0 for s in line)
        y1 = max(s.y1 for s in line)
        return sum(1 for o in column if o.y0 <= y1 and o.y1 >= y0)

    out_left: list[TextSpan] = []
    out_right: list[TextSpan] = []

    for line in _split_into_lines(spans):
        min_x0 = min(s.x0 for s in line)
        max_x1 = max(s.x1 for s in line)
        spans_gutter = min_x0 < mid - _TWO_UP_GUTTER_BAND and max_x1 > mid + _TWO_UP_GUTTER_BAND

        if spans_gutter:
            # A spread-wide title/chapter head: keep the whole line together on
            # whichever half has text at the same height (left on a tie).
            if overlap_count(right_hint, line) > overlap_count(left_hint, line):
                out_right.extend(line)
            else:
                out_left.extend(line)
            continue

        for s in line:
            center = (s.x0 + s.x1) / 2.0
            if center < mid - _TWO_UP_GUTTER_BAND:
                out_left.append(s)
            elif center > mid + _TWO_UP_GUTTER_BAND:
                out_right.append(s)
            elif overlap_count(right_hint, [s]) > overlap_count(left_hint, [s]):
                out_right.append(s)
            else:
                out_left.append(s)

    return [out_left, out_right]


def extract_spans(pdf_path: str, progress_cb=None) -> list[PageExtraction]:
    """Extract raw text spans with layout info from every page of a PDF.

    Pages laid out two book pages side by side (two-up/spread scans) are split
    into two logical pages, left half first then right half, so the reading
    order -- and thus reflowed text -- matches the book instead of
    interleaving the two columns line by line.

    ``progress_cb`` (if given) is called after each physical page with a
    fraction (0.0-1.0) of the document completed, so callers can report live
    progress.
    """
    doc = fitz.open(pdf_path)
    pages: list[PageExtraction] = []
    total = doc.page_count
    logical_index = 0

    for page_index, page in enumerate(doc):
        page_width = page.rect.width
        page_height = page.rect.height
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
                            page_number=logical_index,
                        )
                    )

        # If a page has (almost) no extractable text, it's very likely a
        # scanned image with no embedded text layer -- flag it for OCR.
        # Use character count, not span count: Word-exported PDFs can pack a
        # full page into a handful of long spans, so span count alone would
        # wrongly route text pages to OCR.
        total_chars = sum(len(s.text) for s in spans)
        has_text_layer = total_chars > 15

        _HIGHLIGHT_ANNOTS = {
            fitz.PDF_ANNOT_HIGHLIGHT,
            fitz.PDF_ANNOT_UNDERLINE,
            fitz.PDF_ANNOT_STRIKE_OUT,
            fitz.PDF_ANNOT_SQUIGGLY,
        }
        raw_annots: list[NativeAnnotation] = []
        for ann in page.annots() or []:
            # `ann.type` is a (int, name) tuple in PyMuPDF.
            annot_code = ann.type[0] if isinstance(ann.type, tuple) else ann.type
            if annot_code == fitz.PDF_ANNOT_TEXT:
                kind = "note"
            elif annot_code in _HIGHLIGHT_ANNOTS:
                kind = "highlight"
            else:
                continue  # skip widgets, links, stamps, drawings, etc.
            r = ann.rect
            raw_annots.append(
                NativeAnnotation(
                    x0=r.x0,
                    y0=r.y0,
                    x1=r.x1,
                    y1=r.y1,
                    kind=kind,
                    color=ann.colors.get("stroke") if ann.colors else None,
                    note_text=(ann.info or {}).get("content") or None,
                )
            )

        halves = _split_two_up_spans(spans, page_width) if has_text_layer else None

        def annot_half(annot: NativeAnnotation):
            """Pick left (0) or right (1) half for a raw annotation on a split
            spread, using the same rules as span assignment (prefer the side
            whose text overlaps the annotation, left on a tie)."""
            mid = page_width / 2.0
            center = (annot.x0 + annot.x1) / 2.0
            left_spans, right_spans = halves
            if center < mid - _TWO_UP_GUTTER_BAND:
                return 0
            if center > mid + _TWO_UP_GUTTER_BAND:
                return 1
            left_overlap = sum(
                1 for s in left_spans if s.y0 <= annot.y1 and s.y1 >= annot.y0
            )
            right_overlap = sum(
                1 for s in right_spans if s.y0 <= annot.y1 and s.y1 >= annot.y0
            )
            return 1 if right_overlap > left_overlap else 0

        if halves is None:
            pages.append(
                PageExtraction(
                    page_number=logical_index,
                    spans=spans,
                    has_text_layer=has_text_layer,
                    page_width=page_width,
                    page_height=page_height,
                    pdf_page_index=page_index,
                    native_annotations=raw_annots,
                )
            )
            logical_index += 1
        else:
            buckets = [[], []]
            for annot in raw_annots:
                buckets[annot_half(annot)].append(annot)
            for i, half in enumerate(halves):
                pages.append(
                    PageExtraction(
                        page_number=logical_index,
                        spans=half,
                        has_text_layer=True,
                        page_width=page_width,
                        page_height=page_height,
                        pdf_page_index=page_index,
                        native_annotations=buckets[i],
                    )
                )
                logical_index += 1

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
