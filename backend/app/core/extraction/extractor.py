"""Step 1 of the text-layer pipeline: extract per-page positioned text runs.

Each run carries the same geometry pdf.js exposes through ``getTextContent()``
text items -- a string plus its left origin, baseline, font height and advance
width -- so clients can render the PDF's native text layer exactly like the
lab reader does (fonts, positions, scaleX fitting), with no pdf.js needed.

Pages are physical PDF pages (no two-up splitting): page count, page numbers
and annotation page indexes all refer to the PDF's own pages.
"""

from dataclasses import dataclass, field

import fitz  # PyMuPDF


@dataclass
class TextRun:
    text: str
    x: float  # left of the first character origin, display space
    y: float  # baseline, display space
    font_size: float  # em height (pdf.js fontHeight)
    advance: float  # advance width in page units (pdf.js item.width)
    font: str
    flags: int = 0  # PyMuPDF span flags: 2=italic, 8=mono, 16=bold
    page_index: int = 0


@dataclass
class PageExtraction:
    page_index: int
    runs: list[TextRun]
    has_text_layer: bool  # False => scanned/image-only page, needs OCR
    width: float = 0.0  # display-space page dimensions (rotation applied)
    height: float = 0.0
    rotation: int = 0
    # Native PDF annotations (highlights, underlines, margin notes) found on
    # this page, in display-space coordinates.
    native_annotations: list["NativeAnnotation"] = field(default_factory=list)

    def __post_init__(self):
        for r in self.runs:
            r.page_index = self.page_index


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


def _rotated_dimensions(width: float, height: float, rotation: int) -> tuple[float, float]:
    if rotation in (90, 270):
        return height, width
    return width, height


def _rotate_point(x: float, y: float, width: float, height: float, rotation: int) -> tuple[float, float]:
    """Map an unrotated page point (origin top-left, y down) into display space.

    Matches pdf.js, which renders text items in the rotated viewport space.
    ``width``/``height`` are the unrotated page dimensions.
    """
    if rotation == 90:
        return height - y, x
    if rotation == 180:
        return width - x, height - y
    if rotation == 270:
        return y, width - x
    return x, y


def _rotate_rect(rect: fitz.Rect, width: float, height: float, rotation: int) -> tuple[float, float, float, float]:
    xs, ys = zip(*[_rotate_point(p.x, p.y, width, height, rotation) for p in (rect.tl, rect.tr, rect.br, rect.bl)])
    return min(xs), min(ys), max(xs), max(ys)


def _span_advance(span: dict) -> float:
    """Advance width of a rawdict span: sum of per-character advances.

    The pen position (char origin) between consecutive characters is the true
    advance, so a space between words is naturally included. The final
    character's advance has no successor, so its bbox width is used instead.
    """
    chars = span.get("chars", [])
    if len(chars) >= 2:
        total = 0.0
        for i in range(len(chars) - 1):
            total += max(0.0, chars[i + 1]["origin"][0] - chars[i]["origin"][0])
        last = chars[-1]
        total += max(0.0, last["bbox"][2] - last["bbox"][0])
        return total
    if len(chars) == 1:
        b = chars[0]["bbox"]
        return max(0.0, b[2] - b[0])
    b = span.get("bbox") or (0.0, 0.0, 0.0, 0.0)
    return max(0.0, b[2] - b[0])


_HIGHLIGHT_ANNOTS = {
    fitz.PDF_ANNOT_HIGHLIGHT,
    fitz.PDF_ANNOT_UNDERLINE,
    fitz.PDF_ANNOT_STRIKE_OUT,
    fitz.PDF_ANNOT_SQUIGGLY,
}


def _extract_native_annotations(page: fitz.Page, width: float, height: float, rotation: int) -> list[NativeAnnotation]:
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
        x0, y0, x1, y1 = _rotate_rect(ann.rect, width, height, rotation)
        raw_annots.append(
            NativeAnnotation(
                x0=x0,
                y0=y0,
                x1=x1,
                y1=y1,
                kind=kind,
                color=ann.colors.get("stroke") if ann.colors else None,
                note_text=(ann.info or {}).get("content") or None,
            )
        )
    return raw_annots


def extract_text_runs(pdf_path: str, progress_cb=None, doc: fitz.Document | None = None) -> list[PageExtraction]:
    """Extract positioned text runs from every physical page of a PDF.

    Runs come from PyMuPDF's ``rawdict`` extraction (which yields character
    origins), in document reading order. Pages whose embedded text layer is
    (nearly) empty are flagged with ``has_text_layer=False`` so the caller can
    OCR them.

    ``progress_cb`` (if given) is called after each page with a fraction
    (0.0-1.0) of the document completed. ``doc`` is an already-open document to
    reuse (avoids re-parsing the file); when omitted the PDF is opened and
    closed here.
    """
    own_doc = doc is None
    doc = doc or fitz.open(pdf_path)
    try:
        pages: list[PageExtraction] = []
        total = doc.page_count

        for page_index, page in enumerate(doc):
            rotation = page.rotation or 0
            base_w, base_h = page.rect.width, page.rect.height
            disp_w, disp_h = _rotated_dimensions(base_w, base_h, rotation)
            raw = page.get_text("rawdict")
            runs: list[TextRun] = []

            for block in raw.get("blocks", []):
                for line in block.get("lines", []):
                    for span in line.get("spans", []):
                        # rawdict spans don't carry an aggregated "text" key; the
                        # text is the concatenation of their character dicts.
                        text = "".join(c.get("c", "") for c in span.get("chars", [])).strip()
                        if not text:
                            continue
                        origin = span.get("origin") or (0.0, 0.0)
                        x, y = _rotate_point(origin[0], origin[1], base_w, base_h, rotation)
                        runs.append(
                            TextRun(
                                text=text,
                                x=x,
                                y=y,
                                font_size=span.get("size", 0.0),
                                advance=_span_advance(span),
                                font=span.get("font", ""),
                                flags=span.get("flags", 0),
                                page_index=page_index,
                            )
                        )

            total_chars = sum(len(r.text) for r in runs)
            has_text_layer = total_chars > 15

            pages.append(
                PageExtraction(
                    page_index=page_index,
                    runs=runs,
                    has_text_layer=has_text_layer,
                    width=disp_w,
                    height=disp_h,
                    rotation=rotation,
                    native_annotations=_extract_native_annotations(page, base_w, base_h, rotation),
                )
            )

            if progress_cb:
                progress_cb((page_index + 1) / total)
    finally:
        if own_doc:
            doc.close()
    return pages


def get_pdf_outline(pdf_path: str, doc: fitz.Document | None = None) -> list[dict]:
    """Pull the PDF's built-in bookmarks/outline, if present -- a free,
    reliable source of chapter/heading structure when available.

    Pages are 0-based (matching ``pages[].page`` in the text-layer JSON).
    ``doc`` is an already-open document to reuse; when omitted the PDF is
    opened and closed here.
    """
    own_doc = doc is None
    doc = doc or fitz.open(pdf_path)
    try:
        toc = doc.get_toc()  # [[level, title, page_number(1-based)], ...]
    finally:
        if own_doc:
            doc.close()
    return [{"level": lvl, "title": title, "page": page - 1} for lvl, title, page in toc]
