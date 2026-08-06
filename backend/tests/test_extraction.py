import fitz
import pytest
from unittest import mock

from app.core.extraction.extractor import (
    TextRun,
    extract_text_runs,
    get_pdf_outline,
    _rotate_point,
    _rotated_dimensions,
    _span_advance,
)
from app.core.extraction.annotations import reconcile_native_annotations
from app.core.extraction.coverage import text_coverage
from app.core.extraction.pipeline import run_pipeline


@pytest.fixture
def two_page_pdf(tmp_path):
    """One page with real text, one blank page (stands in for a scan)."""
    path = tmp_path / "book.pdf"
    doc = fitz.open()
    page = doc.new_page(width=612, height=792)
    page.insert_text((72, 96), "David Copperfield", fontsize=20)
    page.insert_text((72, 140), "It was the best of times.", fontsize=12)
    doc.new_page(width=612, height=792)
    doc.set_toc([[1, "Chapter One", 1]])
    doc.save(path)
    doc.close()
    return str(path)


@pytest.fixture
def image_pdf(tmp_path):
    """A page with real text and one embedded raster image."""
    path = tmp_path / "illustrated.pdf"
    doc = fitz.open()
    page = doc.new_page(width=612, height=792)
    page.insert_text((72, 96), "Caption text", fontsize=12)
    pix = fitz.Pixmap(fitz.csRGB, fitz.IRect(0, 0, 120, 80), False)
    pix.clear_with(0)  # solid black
    page.insert_image(fitz.Rect(200, 300, 320, 380), pixmap=pix)
    doc.save(path)
    doc.close()
    return str(path)


# ---------------------------------------------------------------------------
# Positioned-run extraction
# ---------------------------------------------------------------------------


def test_extract_text_runs_physical_pages_and_run_geometry(two_page_pdf):
    pages = extract_text_runs(two_page_pdf)

    # Physical pages: the two-column spread PDF is NOT split into logical pages.
    assert len(pages) == 2
    assert pages[0].page_index == 0
    assert pages[1].page_index == 1

    assert pages[0].has_text_layer is True
    assert pages[1].has_text_layer is False  # blank page -> OCR candidate

    assert pages[0].width == 612.0
    assert pages[0].height == 792.0

    runs = pages[0].runs
    assert runs, "expected text runs on page 0"
    joined = " ".join(r.text for r in runs)
    assert "David Copperfield" in joined

    for r in runs:
        assert r.x >= 0 and r.y >= 0
        assert r.font_size > 0
        assert r.advance > 0
        assert r.font
        assert r.page_index == 0


def test_extract_page_images_finds_embedded_raster(image_pdf):
    pages = extract_text_runs(image_pdf)

    assert len(pages) == 1
    page = pages[0]
    assert page.width == 612.0 and page.height == 792.0

    assert len(page.images) == 1
    img = page.images[0]
    # Placed at Rect(200, 300, 320, 380) unrotated; rotation 0 -> identity.
    assert img.x0 == pytest.approx(200.0, abs=0.1)
    assert img.y0 == pytest.approx(300.0, abs=0.1)
    assert img.x1 == pytest.approx(320.0, abs=0.1)
    assert img.y1 == pytest.approx(380.0, abs=0.1)
    assert img.data, "image bytes must be extracted"
    assert img.ext in ("png", "jpg")

    # Decode the stored bytes back into an image with the same aspect ratio
    # (JPEG encoding may round dimensions down to DCT block multiples).
    with fitz.open(stream=img.data, filetype=img.ext) as imgsrc:
        pix = imgsrc[0].get_pixmap()
        assert pix.width / pix.height == pytest.approx(120 / 80, rel=0.05)


def test_pipeline_emits_images_when_uploader_passed(image_pdf):
    uploaded = []

    def fake_uploader(data: bytes, ext: str) -> str:
        uploaded.append(ext)
        return f"images/owner/{len(uploaded)}.{ext}"

    result = run_pipeline(image_pdf, image_uploader=fake_uploader)

    assert len(result["pages"]) == 1
    page = result["pages"][0]
    assert len(page["images"]) == 1
    img = page["images"][0]
    assert img["key"].startswith("images/owner/")
    assert img["x"] == pytest.approx(200.0, abs=0.1)
    assert img["y"] == pytest.approx(300.0, abs=0.1)
    assert img["w"] == pytest.approx(120.0, abs=0.1)
    assert img["h"] == pytest.approx(80.0, abs=0.1)
    assert uploaded == [img["key"].rsplit(".", 1)[1]]


def test_pipeline_omits_image_keys_without_uploader(image_pdf):
    result = run_pipeline(image_pdf)
    assert len(result["pages"][0]["images"]) == 1
    assert result["pages"][0]["images"][0]["key"] is None


def test_two_up_spread_is_not_split(tmp_path):
    """A two-column spread stays ONE physical page (no logical splitting)."""
    path = tmp_path / "spread.pdf"
    doc = fitz.open()
    page = doc.new_page(width=800, height=600)
    for i in range(10):
        page.insert_text((80, 100 + i * 24), f"left line {i}", fontsize=12)
        page.insert_text((460, 100 + i * 24), f"right line {i}", fontsize=12)
    doc.save(path)
    doc.close()

    pages = extract_text_runs(path)
    assert len(pages) == 1
    assert pages[0].width == 800.0
    assert len(pages[0].runs) == 20


def test_rotation_transform():
    assert _rotated_dimensions(612, 792, 0) == (612, 792)
    assert _rotated_dimensions(612, 792, 90) == (792, 612)
    assert _rotated_dimensions(612, 792, 270) == (792, 612)
    assert _rotated_dimensions(612, 792, 180) == (612, 792)

    # 90 deg clockwise: a point at the top-left stays top-left of display space.
    assert _rotate_point(0, 0, 612, 792, 90) == (792, 0)
    assert _rotate_point(72, 96, 612, 792, 90) == (792 - 96, 72)
    # 180 deg: flips both axes.
    assert _rotate_point(72, 96, 612, 792, 180) == (612 - 72, 792 - 96)


def test_span_advance_sums_char_pen_positions():
    chars = [
        {"c": "a", "origin": [72.0, 96.0], "bbox": [72.0, 88.0, 79.0, 96.0]},
        {"c": "b", "origin": [79.0, 96.0], "bbox": [79.0, 88.0, 86.0, 96.0]},
        {"c": "c", "origin": [86.0, 96.0], "bbox": [86.0, 88.0, 93.0, 96.0]},
    ]
    assert _span_advance({"chars": chars}) == pytest.approx(21.0)  # 7 + 7 + 7


def test_text_coverage():
    assert text_coverage(3, 4) == 0.75
    assert text_coverage(0, 4) == 0.0
    assert text_coverage(4, 4) == 1.0
    assert text_coverage(1, 0) == 0.0


def test_get_pdf_outline_uses_zero_based_pages(two_page_pdf):
    outline = get_pdf_outline(two_page_pdf)
    assert outline == [{"level": 1, "title": "Chapter One", "page": 0}]


# ---------------------------------------------------------------------------
# Native PDF annotation import (char-range anchors)
# ---------------------------------------------------------------------------


def _page(runs, annots):
    from app.core.extraction.extractor import PageExtraction, NativeAnnotation

    return PageExtraction(
        page_index=0,
        runs=[TextRun(text=t, x=x, y=y, font_size=fs, advance=w, font="Body", page_index=0) for t, x, y, fs, w in runs],
        has_text_layer=True,
        width=612.0,
        height=792.0,
        native_annotations=annots,
    )


def test_native_highlight_anchored_by_char_range():
    from app.core.extraction.extractor import NativeAnnotation

    page = _page(
        runs=[
            ("The quick brown fox", 50.0, 40.0, 12.0, 150.0),
            ("jumps over the lazy dog.", 50.0, 54.0, 12.0, 180.0),
            ("An untouched following line.", 50.0, 68.0, 12.0, 190.0),
        ],
        annots=[NativeAnnotation(x0=48.0, y0=28.0, x1=380.0, y1=54.0, kind="highlight", color=(1.0, 0.8, 0.2))],
    )

    result = reconcile_native_annotations([page])

    assert len(result) == 1
    ann = result[0]
    assert ann["kind"] == "highlight"
    assert ann["color"] == "#FFCC33"
    assert ann["page"] == 0
    assert ann["text"] == "The quick brown fox jumps over the lazy dog."
    assert ann["anchor"]["start_char"] == 0
    assert ann["anchor"]["end_char"] == len("The quick brown fox" + "jumps over the lazy dog.")
    assert "An untouched following line." in ann["anchor"]["context_after"]


def test_native_note_without_overlap_falls_back_to_page_anchor():
    from app.core.extraction.extractor import NativeAnnotation

    page = _page(
        runs=[("Just body text here.", 50.0, 40.0, 12.0, 150.0)],
        annots=[NativeAnnotation(x0=560.0, y0=80.0, x1=590.0, y1=110.0, kind="note", note_text="Margin thought")],
    )

    result = reconcile_native_annotations([page])

    assert len(result) == 1
    assert result[0]["kind"] == "note"
    assert result[0]["text"] == ""
    assert result[0]["note"] == "Margin thought"
    assert result[0]["anchor"]["page"] == 0
    assert result[0]["anchor"]["start_char"] is None


# ---------------------------------------------------------------------------
# Pipeline end to end
# ---------------------------------------------------------------------------


def test_pipeline_schema_and_coverage(two_page_pdf):
    result = run_pipeline(two_page_pdf)

    assert result["schema"] == "textlayer-v1"
    assert result["outline"] == [{"level": 1, "title": "Chapter One", "page": 0}]
    assert result["text_confidence"] == 0.5  # 1 of 2 pages has text
    assert result["reflow_confidence"] == 0.5
    # At exactly 50% coverage the book is still "half text" -> not a scan, and
    # the text layer is recommended.
    assert result["is_scanned"] is False
    assert result["reflow_mode_recommended"] is True

    assert len(result["pages"]) == 2
    p0 = result["pages"][0]
    assert p0["page"] == 0 and p0["width"] == 612.0 and p0["height"] == 792.0
    assert any("David Copperfield" in r["t"] for r in p0["runs"])
    for r in p0["runs"]:
        assert set(("t", "x", "y", "fs", "w", "f", "flags")) <= set(r.keys())


def test_pipeline_ocr_fallback_fills_blank_page(two_page_pdf):
    from app.core.extraction.extractor import TextRun

    def fake_ocr(pdf_path, page_number):
        assert page_number == 1
        return [TextRun(text="Scanned line one", x=50.0, y=60.0, font_size=24.0, advance=120.0, font="ocr", page_index=1)], 0.9

    with mock.patch("app.core.extraction.ocr.ocr_page", side_effect=fake_ocr):
        result = run_pipeline(two_page_pdf)

    assert len(result["pages"]) == 2
    ocr_page = result["pages"][1]
    assert any("Scanned line one" in r["t"] for r in ocr_page["runs"])
    # Both pages now render text -> full coverage.
    assert result["text_confidence"] == 1.0
    assert result["is_scanned"] is False


def test_pipeline_low_confidence_ocr_is_dropped(two_page_pdf):
    def fake_ocr(pdf_path, page_number):
        return [TextRun(text="Garbage", x=0.0, y=0.0, font_size=12.0, advance=10.0, font="ocr", page_index=1)], 0.2

    with mock.patch("app.core.extraction.ocr.ocr_page", side_effect=fake_ocr):
        result = run_pipeline(two_page_pdf)

    assert result["pages"][1]["runs"] == []
    assert result["text_confidence"] == 0.5
