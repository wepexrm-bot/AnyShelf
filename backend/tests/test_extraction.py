from app.core.extraction.extractor import TextSpan, _split_two_up_spans
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


def _two_up_span(text, x0, y0, size=12.0):
    return TextSpan(
        text=text,
        x0=x0,
        y0=y0,
        x1=x0 + len(text) * 6,
        y1=y0 + size,
        font="Body",
        size=size,
        page_number=0,
    )


def test_two_up_split_separates_left_and_right_columns():
    # 612pt-wide sheet with a full left column (x 65-300) and full right
    # column (x 315-556), matching baselines -- a classic spread layout.
    spans = []
    for i in range(10):
        spans.append(_two_up_span(f"left line {i}", 65.0, 30 + i * 14))
        spans.append(_two_up_span(f"right line {i}", 320.0, 30 + i * 14))

    halves = _split_two_up_spans(spans, 612.0)

    assert halves is not None
    left, right = halves
    assert all(s.x1 <= 306 for s in left)
    assert all(s.x0 >= 306 for s in right)
    assert len(left) == 10
    assert len(right) == 10


def test_two_up_split_keeps_centered_chapter_head_with_left_column():
    # A spread whose left half opens a chapter: the centered title straddles
    # the center line but must stay with the left column (its body text), not
    # leak into the right page.
    spans = []
    for i in range(10):
        spans.append(_two_up_span(f"left line {i}", 65.0, 90 + i * 14))
        spans.append(_two_up_span(f"right line {i}", 320.0, 90 + i * 14))
    spans.append(_two_up_span("CHAPTER I.", 270.0, 50.0, size=20.0))

    halves = _split_two_up_spans(spans, 612.0)

    assert halves is not None
    left, right = halves
    assert any(s.text == "CHAPTER I." for s in left)
    assert not any(s.text == "CHAPTER I." for s in right)


def test_two_up_split_keeps_fragmented_centered_title_together():
    # PDFs fragment a spread-wide book title into many tiny spans whose
    # horizontal centers fall on both sides of the gutter. The whole line must
    # stay on one side so the title doesn't break across the two halves.
    spans = []
    for i in range(10):
        spans.append(_two_up_span(f"left line {i}", 65.0, 90 + i * 14))
        spans.append(_two_up_span(f"right line {i}", 320.0, 90 + i * 14))
    fragments = ["M", "r", ". S", "herlock", "H", "olmes"]
    x = 247.0
    for frag in fragments:
        spans.append(_two_up_span(frag, x, 50.0, size=20.0))
        x += len(frag) * 6

    halves = _split_two_up_spans(spans, 612.0)

    assert halves is not None
    left, right = halves
    left_text = "".join(s.text for s in left).replace(" ", "")
    right_text = "".join(s.text for s in right).replace(" ", "")
    assert "Mr.SherlockHolmes" in left_text
    assert "Mr.SherlockHolmes" not in right_text


def test_two_up_split_rejects_single_full_width_page():
    # A normal book page is justified across the full width, so nearly every
    # span crosses the center line -- that must NOT be split.
    spans = [_two_up_span(f"line {i}", 65.0, 30 + i * 14, size=12.0) for i in range(12)]
    spans = [TextSpan(text=s.text, x0=65.0, y0=s.y0, x1=550.0, y1=s.y1, font="Body", size=12.0, page_number=0) for s in spans]

    assert _split_two_up_spans(spans, 612.0) is None


def test_two_up_split_rejects_centered_title_page():
    # A title page is centered around the middle of the sheet, not split into
    # two columns.
    spans = [_two_up_span("A Study in Scarlet", 250.0, 50.0, size=20.0)]
    spans.append(_two_up_span("by Arthur Conan Doyle", 240.0, 80.0, size=14.0))

    assert _split_two_up_spans(spans, 612.0) is None


# --------------------------------------------------------------------------
# Native PDF annotation import
# --------------------------------------------------------------------------

from app.core.extraction.annotations import reconcile_native_annotations
from app.core.extraction.extractor import NativeAnnotation, PageExtraction


def _annot_page(spans, raw_annots):
    return PageExtraction(
        page_number=0,
        spans=spans,
        has_text_layer=True,
        page_width=612.0,
        page_height=792.0,
        native_annotations=raw_annots,
    )


def test_native_highlight_is_anchored_by_matched_text():
    spans = [
        make_span("The quick brown fox", y0=30.0, x0=50.0),
        make_span("jumps over the lazy dog.", y0=44.0, x0=50.0),
        make_span("An untouched following line.", y0=58.0, x0=50.0),
    ]
    # Rectangle covering the first two lines.
    annot = NativeAnnotation(x0=48.0, y0=28.0, x1=380.0, y1=55.0, kind="highlight", color=(1.0, 0.8, 0.2))
    page = _annot_page(spans, [annot])

    result = reconcile_native_annotations([page])

    assert len(result) == 1
    ann = result[0]
    assert ann["kind"] == "highlight"
    assert ann["color"] == "#FFCC33"
    assert ann["page"] == 0
    assert ann["text"] == "The quick brown fox jumps over the lazy dog."
    # Surrounding context picks up the following line so repeated phrases are
    # disambiguated.
    assert "An untouched following line." in ann["anchor"]["context_after"]


def test_native_note_without_overlap_falls_back_to_page_anchor():
    spans = [make_span("Just body text here.", y0=30.0, x0=50.0)]
    # A margin note whose rectangle covers no text at all.
    annot = NativeAnnotation(x0=560.0, y0=80.0, x1=590.0, y1=110.0, kind="note", note_text="Margin thought")
    page = _annot_page(spans, [annot])

    result = reconcile_native_annotations([page])

    assert len(result) == 1
    assert result[0]["kind"] == "note"
    assert result[0]["text"] == ""
    assert result[0]["note"] == "Margin thought"
    assert result[0]["anchor"]["page"] == 0

