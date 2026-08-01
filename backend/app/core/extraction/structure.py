"""Step 3: reconstruct paragraphs/headings from ordered spans, and produce a
confidence score that decides whether a book gets full reflow mode or falls
back to fixed-layout + theme-only mode.

Two extra concerns are handled here that matter a lot for Word-exported PDFs:
  1. Robust line grouping. Word exports a page as hundreds of tiny spans with
     slightly jittered baselines; a fixed y-threshold splits lines in half.
     We group by vertical-overlap tolerance scaled to font size instead.
  2. Running-header/page-number noise. Word puts the document title in a
     header on every page and numbers each page. These repeat identically in
     the same page band, so we can detect and drop them, otherwise they pollute
     the reflowed body text.
"""

import re
from collections import Counter
from dataclasses import dataclass, field
from statistics import median

from app.core.extraction.extractor import TextSpan


@dataclass
class Block:
    kind: str  # "heading" | "paragraph"
    text: str
    level: int = 0  # heading level, 0 for paragraphs


@dataclass
class StructuredPage:
    page_number: int
    blocks: list[Block] = field(default_factory=list)


@dataclass
class Line:
    text: str
    y0: float
    y1: float
    x0: float
    x1: float
    avg_size: float
    page_number: int


def _body_font_size(spans: list[TextSpan]) -> float:
    sizes = [s.size for s in spans if s.text]
    return median(sizes) if sizes else 12.0


def group_into_lines(spans: list[TextSpan]) -> list[Line]:
    """Group spans into visual lines. Spans on the same text line share a
    vertical band, so we accept a span into a line if its baseline is within a
    font-size-scaled tolerance of the line's baseline (survives Word's tiny
    per-span baseline jitter), else it starts a new line."""
    if not spans:
        return []

    body_size = _body_font_size(spans)
    tolerance = max(2.0, body_size * 0.55)

    ordered = sorted(spans, key=lambda s: (s.y0, s.x0))
    line_spans: list[list[TextSpan]] = []

    for span in ordered:
        placed = False
        for line in line_spans:
            line_baseline = sum(s.y0 for s in line) / len(line)
            if abs(span.y0 - line_baseline) < tolerance:
                line.append(span)
                placed = True
                break
        if not placed:
            line_spans.append([span])

    lines: list[Line] = []
    for group in line_spans:
        group.sort(key=lambda s: s.x0)
        text = _join_line_text(group)
        lines.append(
            Line(
                text=text,
                y0=min(s.y0 for s in group),
                y1=max(s.y1 for s in group),
                x0=min(s.x0 for s in group),
                x1=max(s.x1 for s in group),
                avg_size=sum(s.size for s in group) / len(group),
                page_number=group[0].page_number,
            )
        )
    return lines


def _join_line_text(spans: list[TextSpan]) -> str:
    """Join spans on one line into readable text. Insert a space only when
    there's a real horizontal gap between spans (handles both tightly-set
    words and per-word spans without double-spacing)."""
    text = ""
    prev_end = None
    for s in spans:
        if prev_end is not None and s.x0 - prev_end > 1.0:
            text += " " + s.text
        else:
            text += s.text
        if prev_end is None or s.x1 > prev_end:
            prev_end = s.x1
    return re.sub(r"\s+", " ", text).strip()


_PAGE_NUMBER_RE = re.compile(r"^\s*[-–—.·•*]?\s*(\d+|[ivxlcdm]+)\s*[-–—.·•*]?\s*$", re.IGNORECASE)
_PAGE_NUMBER_LABEL_RE = re.compile(r"^\s*(page|p\.?|no\.?|n\.?o\.?)\s*\d+\s*$", re.IGNORECASE)
_HEADER_FOOTER_BAND = 0.08  # fraction of page height treated as header/footer margin


def _strip_trailing_page_number(text: str) -> str:
    """Word often formats its running header as '<CHAPTER> <Title> <page#>',
    so the text differs per page only by the trailing page number. Normalize
    that away so repeated headers are still recognized across pages."""
    return re.sub(r"\s+(?:[-–—.·•*]*\s*(?:\d+|[ivxlcdm]+)\s*[-–—.·•*]*)$", "", text.strip(), flags=re.IGNORECASE)


def filter_running_noise(lines_by_page: list[list[Line]], page_heights: list[float]) -> list[list[Line]]:
    """Drop running headers/footers and bare page numbers.

    A line is considered a running header/footer if its text (with any trailing
    page number normalized away) repeats on a majority of pages in the same
    top/bottom band (Word's default header behavior). Bare page-number lines
    (digits or roman numerals, optionally with a label like "Page 12") are
    dropped wherever they appear.
    """
    if not lines_by_page:
        return lines_by_page

    page_count = len(lines_by_page)
    # Chapter running headers/footers only cover the pages of that chapter
    # (as few as 5-15 pages), so use a small fixed threshold. The top/bottom
    # margin-band check plus the 80-char cap already keep body text out of
    # consideration, making false positives rare.
    repeat_threshold = max(4, int(page_count * 0.01))

    band_lines: list[str] = []
    for lines, height in zip(lines_by_page, page_heights):
        for line in lines:
            if not line.text:
                continue
            band_top = height * _HEADER_FOOTER_BAND
            band_bottom = height * (1 - _HEADER_FOOTER_BAND)
            if line.y0 < band_top or line.y1 > band_bottom:
                band_lines.append(_strip_trailing_page_number(line.text))

    text_counts = Counter(band_lines)
    running_texts = {text for text, count in text_counts.items() if count >= repeat_threshold and len(text) <= 80}

    filtered: list[list[Line]] = []
    for lines, height in zip(lines_by_page, page_heights):
        kept: list[Line] = []
        for line in lines:
            text = line.text
            if not text:
                continue
            if _PAGE_NUMBER_RE.match(text) or _PAGE_NUMBER_LABEL_RE.match(text):
                continue
            band_top = height * _HEADER_FOOTER_BAND
            band_bottom = height * (1 - _HEADER_FOOTER_BAND)
            in_margin = line.y0 < band_top or line.y1 > band_bottom
            if in_margin and _strip_trailing_page_number(text) in running_texts:
                continue
            kept.append(line)
        filtered.append(kept)

    return filtered


def reconstruct_blocks_from_lines(lines: list[Line]) -> list[Block]:
    """Group lines into paragraphs (and flag headings) using the line
    metadata already computed during grouping."""
    if not lines:
        return []

    body_size = median(line.avg_size for line in lines) if lines else 12.0
    gaps = [lines[i].y0 - lines[i - 1].y1 for i in range(1, len(lines))]
    positive_gaps = [g for g in gaps if g > 0]
    typical_gap = median(positive_gaps) if positive_gaps else max(body_size * 0.5, 2.0)

    blocks: list[Block] = []
    paragraph_buffer: list[str] = []

    def flush_paragraph():
        if paragraph_buffer:
            blocks.append(Block(kind="paragraph", text=" ".join(paragraph_buffer)))
            paragraph_buffer.clear()

    for i, line in enumerate(lines):
        is_heading = line.avg_size > body_size * 1.25 and len(line.text) < 120

        if is_heading:
            flush_paragraph()
            level = 1 if line.avg_size > body_size * 1.6 else 2
            blocks.append(Block(kind="heading", text=line.text, level=level))
            continue

        # A vertical gap much larger than the line-to-line spacing starts a
        # new paragraph.
        if i > 0 and (lines[i].y0 - lines[i - 1].y1) > typical_gap * 1.8:
            flush_paragraph()

        paragraph_buffer.append(line.text)

    flush_paragraph()
    return blocks


def reconstruct_blocks(ordered_spans: list[TextSpan], line_gap_threshold: float = 4.0) -> list[Block]:
    """Backwards-compatible entry point: group ordered spans into lines, then
    lines into paragraphs, and flag headings by font size vs. body baseline."""
    if not ordered_spans:
        return []
    lines = group_into_lines(ordered_spans)
    return reconstruct_blocks_from_lines(lines)


def score_reflow_confidence(
    pages: list[StructuredPage], scanned_page_ratio: float, outline: list | None = None
) -> float:
    """Rough 0.0-1.0 confidence that reflow mode will render well.

    The strongest signals are (a) a real text layer that produced output
    (presence) rather than raw density, and (b) no scanned pages. Density and
    block structure only refine the estimate -- a one-page declaration form is
    perfectly reflowable even though it is far denser-fewer chars than a novel.
    """
    if not pages:
        return 0.0

    total_chars = sum(len(b.text) for p in pages for b in p.blocks)
    avg_chars_per_page = total_chars / len(pages)

    # Presence: did extraction actually recover readable text? Saturates
    # quickly (~400 chars/page); a page with this much real text is reflowable
    # regardless of whether it's a dense novel or a short form.
    presence_score = min(avg_chars_per_page / 400.0, 1.0)

    # Density only slightly refines: very high density is a bonus, not a
    # requirement.
    density_score = min(avg_chars_per_page / 1500.0, 1.0)

    avg_blocks_per_page = sum(len(p.blocks) for p in pages) / len(pages)
    structure_score = min(avg_blocks_per_page / 6.0, 1.0)

    confidence = 0.6 * presence_score + 0.2 * density_score + 0.2 * structure_score

    # A real outline (chapters/headings) is strong evidence of a
    # well-structured, reflowable text PDF.
    if outline:
        confidence += 0.15

    scan_penalty = scanned_page_ratio  # 0 = no scanned pages, 1 = all scanned
    confidence *= 1 - scan_penalty

    return round(max(0.0, min(confidence, 1.0)), 2)
