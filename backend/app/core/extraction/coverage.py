"""Text-layer coverage: how much of a book has usable text runs.

Replaces the old reflow-confidence scoring. With positioned text runs the
question is simply "can every page render text?" A scanned page (OCR'd or
blank) still renders, but pages with neither a text layer nor OCR drag the
coverage score down, and a book whose pages are mostly image-only should be
treated as a fixed-PDF book.
"""


def text_coverage(pages_with_text: int, total_pages: int) -> float:
    """Fraction of pages that contributed text runs (0.0-1.0)."""
    if total_pages <= 0:
        return 0.0
    return round(max(0.0, min(pages_with_text / total_pages, 1.0)), 2)
