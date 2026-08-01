"""Step 2: reconstruct correct reading order from raw text spans.

Native PDF text extraction gives spans in whatever order they were drawn,
which does NOT reliably match reading order -- especially for multi-column
layouts. This clusters spans into columns by x-position, then orders each
column top-to-bottom, then columns left-to-right.
"""

from app.core.extraction.extractor import TextSpan


def detect_columns(spans: list[TextSpan], page_width: float, gap_threshold: float = 20.0) -> list[list[TextSpan]]:
    """Group spans into vertical columns based on horizontal gaps between
    clusters of x0 positions. Works well for simple 1-3 column layouts;
    complex magazine-style layouts may need a more sophisticated approach."""
    if not spans:
        return []

    sorted_spans = sorted(spans, key=lambda s: s.x0)
    columns: list[list[TextSpan]] = [[sorted_spans[0]]]

    for span in sorted_spans[1:]:
        last_column = columns[-1]
        last_max_x = max(s.x1 for s in last_column)
        if span.x0 - last_max_x > gap_threshold:
            columns.append([span])
        else:
            last_column.append(span)

    return columns


def order_reading_sequence(spans: list[TextSpan], page_width: float) -> list[TextSpan]:
    """Return spans in correct reading order: column by column (left to
    right), top to bottom within each column."""
    columns = detect_columns(spans, page_width)
    ordered: list[TextSpan] = []

    for column in columns:
        column_sorted = sorted(column, key=lambda s: (s.y0, s.x0))
        ordered.extend(column_sorted)

    return ordered
