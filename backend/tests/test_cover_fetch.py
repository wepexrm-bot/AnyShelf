"""Tests for automatic book-cover lookup (app.core.cover_fetch)."""

import asyncio

import httpx
import pytest

from app.core.cover_fetch import _try_open_library, fetch_cover

SEARCH_URL = "https://openlibrary.org/search.json"
COVER_URL = "https://covers.openlibrary.org/b/id/{cover_id}-L.jpg"
COVER_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 2000  # > _MIN_IMAGE_BYTES


class _FakeResponse:
    def __init__(self, status_code=200, json_data=None, content=b"", headers=None):
        self.status_code = status_code
        self._json_data = json_data
        self.content = content
        self.headers = headers or {"content-type": "image/jpeg"}

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("error", request=httpx.Request("GET", "url"), response=self)

    def json(self):
        return self._json_data


class _FakeClient:
    """Records GETs and serves canned responses by URL/path pattern."""

    def __init__(self, search_results, cover_results):
        # search_results: list of docs lists, one per search call in order.
        self.search_calls = []
        self.cover_calls = []
        self._search_results = list(search_results)
        self._cover_results = list(cover_results)

    async def get(self, url, params=None):
        if url == SEARCH_URL:
            self.search_calls.append(dict(params))
            docs = self._search_results.pop(0) if self._search_results else []
            return _FakeResponse(json_data={"docs": docs})
        self.cover_calls.append(url)
        content = self._cover_results.pop(0) if self._cover_results else COVER_BYTES
        return _FakeResponse(content=content)


class _AsyncClientManager:
    """Context manager yielding the fake client for fetch_cover's httpx use."""

    def __init__(self, fake):
        self._fake = fake

    async def __aenter__(self):
        return self._fake

    async def __aexit__(self, *exc):
        return False


@pytest.fixture(autouse=True)
def _no_real_network(monkeypatch):
    """Prevent accidental network calls outside the fakes."""

    def _fail(*args, **kwargs):
        raise AssertionError("Unexpected network call in cover-fetch test")

    monkeypatch.setattr(
        "app.core.cover_fetch.httpx.AsyncClient",
        lambda **kwargs: _AsyncClientManager(_FakeClient([], [])),
    )


def test_title_only_query_sent_first_and_cover_returned():
    """The title-only phrase is the first search, and a cover is returned."""
    client = _FakeClient(
        search_results=[[{"title": "Harry Potter and the Cursed Child", "cover_i": 8763851}]],
        cover_results=[],
    )
    result = asyncio.run(_try_open_library(client, "Harry Potter and the Cursed Child", "R.K. Rowling"))
    assert client.search_calls[0] == {"q": '"Harry Potter and the Cursed Child"', "limit": 10}
    assert result == (COVER_BYTES, "image/jpeg")
    assert client.cover_calls == [COVER_URL.format(cover_id=8763851)]


def test_falls_back_to_title_author_phrase_when_title_only_is_empty():
    """Title-only search returns no docs -> combined phrase is tried."""
    client = _FakeClient(
        search_results=[
            [],  # title-only: no docs
            [{"title": "The Silent Patient", "cover_i": 9407338}],
        ],
        cover_results=[],
    )
    result = asyncio.run(_try_open_library(client, "The Silent Patient", "Michaelides"))
    assert client.search_calls[1] == {"q": "The Silent Patient Michaelides", "limit": 10}
    assert result == (COVER_BYTES, "image/jpeg")


def test_exact_title_match_preferred_over_substring():
    """An exact title match ranks above a loose one for the same query."""
    client = _FakeClient(
        search_results=[
            [
                {"title": "The Hobbit: The Annotated Edition", "cover_i": 1},
                {"title": "The Hobbit", "cover_i": 2},
            ]
        ],
        cover_results=[],
    )
    result = asyncio.run(_try_open_library(client, "The Hobbit", "Tolkien"))
    assert result == (COVER_BYTES, "image/jpeg")
    assert client.cover_calls == [COVER_URL.format(cover_id=2)]


def test_returns_none_when_no_cover_found():
    """Both queries searched, no cover_i anywhere -> None, no image fetched."""
    client = _FakeClient(
        search_results=[
            [{"title": "Dune", "cover_i": None}],
            [{"title": "Dune", "cover_i": None}],
        ],
        cover_results=[],
    )
    result = asyncio.run(_try_open_library(client, "Dune", "Herbert"))
    assert result is None
    assert client.cover_calls == []


def test_fetch_cover_short_circuits_on_open_library_hit(monkeypatch):
    """fetch_cover returns an Open Library cover without calling Google Books."""
    fake = _FakeClient(
        search_results=[[{"title": "The Hobbit", "cover_i": 14627509}]],
        cover_results=[],
    )
    monkeypatch.setattr(
        "app.core.cover_fetch.httpx.AsyncClient",
        lambda **kwargs: _AsyncClientManager(fake),
    )
    result = asyncio.run(fetch_cover("The Hobbit", "Tolkien"))
    assert result == (COVER_BYTES, "image/jpeg")
    assert fake.cover_calls == [COVER_URL.format(cover_id=14627509)]
