from app.core.extraction.extractor import TextSpan
from app.core.extraction.structure import (
    Line,
    filter_running_noise,
    group_into_lines,
    reconstruct_blocks,
    reconstruct_blocks_from_lines,
    score_reflow_confidence,
    StructuredPage,
    Block,
)


def make_span(text, y0, size=12.0, x0=0.0):
    return TextSpan(text=text, x0=x0, y0=y0, x1=x0 + len(text) * 6, y1=y0 + size, font="Body", size=size, page_number=0)


def test_reconstruct_blocks_detects_heading():
    spans = [
        make_span("Chapter One", y0=0, size=20.0),
        make_span("It was a dark and stormy night,", y0=30, size=12.0),
        make_span("the wind howled through the trees.", y0=44, size=12.0),
    ]

    blocks = reconstruct_blocks(spans)

    assert blocks[0].kind == "heading"
    assert blocks[0].text == "Chapter One"
    assert blocks[1].kind == "paragraph"
    assert "dark and stormy" in blocks[1].text


def test_reflow_confidence_penalizes_scanned_pages():
    page = StructuredPage(page_number=0, blocks=[])
    clean_score = score_reflow_confidence([page], scanned_page_ratio=0.0)
    scanned_score = score_reflow_confidence([page], scanned_page_ratio=1.0)

    assert scanned_score <= clean_score


def test_reflow_confidence_rewards_dense_text_and_outline():
    # A single-column novel page has few blocks but lots of text -- the
    # scorer must treat that as reflowable rather than penalizing it.
    body = StructuredPage(
        page_number=0,
        blocks=[Block(kind="paragraph", text="word " * 400)],
    )
    no_outline = score_reflow_confidence([body], scanned_page_ratio=0.0)
    with_outline = score_reflow_confidence([body], scanned_page_ratio=0.0, outline=[{"title": "Ch 1"}])

    assert no_outline >= 0.5
    assert with_outline > no_outline


def _line(text, y0, y1=None, size=12.0):
    return Line(
        text=text,
        y0=y0,
        y1=y1 if y1 is not None else y0 + 14.0,
        x0=0.0,
        x1=len(text) * 6,
        avg_size=size,
        page_number=0,
    )


def test_group_into_lines_merges_jittered_word_spans():
    # Word-exported PDFs split one visual line into many spans whose baselines
    # jitter by a few points -- they must still be grouped into a single line.
    spans = [
        TextSpan(text="Hello", x0=0.0, y0=100.0, x1=30.0, y1=112.0, font="Body", size=12.0, page_number=0),
        TextSpan(text="cruel", x0=35.0, y0=101.5, x1=65.0, y1=113.5, font="Body", size=12.0, page_number=0),
        TextSpan(text="world", x0=70.0, y0=100.8, x1=105.0, y1=112.8, font="Body", size=12.0, page_number=0),
        TextSpan(text="Next", x0=0.0, y0=120.0, x1=30.0, y1=132.0, font="Body", size=12.0, page_number=0),
    ]

    lines = group_into_lines(spans)

    assert len(lines) == 2
    assert lines[0].text == "Hello cruel world"
    assert lines[1].text == "Next"


def test_filter_running_noise_removes_headers_and_page_numbers():
    # Simulate 10 pages, each with a repeating header "David Copperfield", a
    # footer page number "42", and one line of real body text.
    page_heights = [800.0] * 10
    pages = []
    for i in range(10):
        pages.append([
            _line("David Copperfield", 20.0),
            _line("42", 40.0),
            _line(f"Body text line {i}", 400.0),
        ])

    filtered = filter_running_noise(pages, page_heights)

    # The running header and page number are gone; body text survives.
    for i, page in enumerate(filtered):
        texts = [l.text for l in page]
        assert "David Copperfield" not in texts
        assert "42" not in texts
        assert f"Body text line {i}" in texts


def test_reconstruct_blocks_from_lines_splits_paragraphs():
    # Realistic 12pt body text: line pitch ~14pt, inter-line gaps ~2pt.
    # The paragraph break has a clearly larger gap.
    lines = [
        _line("Chapter One", 0.0, y1=20.0, size=20.0),
        _line("It was a dark and stormy night,", 26.0, y1=38.0),
        _line("the wind howled through the trees.", 40.0, y1=52.0),
        _line("She walked for a long time.", 72.0, y1=84.0),  # gap 20 => new paragraph
    ]

    blocks = reconstruct_blocks_from_lines(lines)

    assert blocks[0].kind == "heading"
    assert blocks[0].text == "Chapter One"
    assert blocks[1].kind == "paragraph"
    assert "stormy" in blocks[1].text
    assert blocks[2].kind == "paragraph"
    assert blocks[2].text == "She walked for a long time."
