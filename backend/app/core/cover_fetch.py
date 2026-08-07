"""Automatic book-cover lookup by title/author.

No AI image generation and no placeholder art here -- this only returns a
cover when a real published edition is actually found. If nothing matches,
callers should leave the book without a cover rather than substituting
anything synthetic.

Tries, in order:
  1. Open Library (keyless, reliable, no aggressive rate limiting) --
     full-text search with a title-match preference, then fetches the cover
     image. Covers API returns a 302 redirect, so redirects are followed.
  2. Google Books API (best hit rate, no key required) -- with one retry on
     transient/rate-limit responses, since it throttles keyless callers.

Both calls are best-effort: network errors, rate limits, or no-match results
are all treated the same way -- log and return None. A cover lookup failing
should never fail the book upload itself.
"""

from __future__ import annotations

import asyncio
import logging
import re

import httpx

logger = logging.getLogger("cloudread.cover_fetch")

GOOGLE_BOOKS_API = "https://www.googleapis.com/books/v1/volumes"
OPEN_LIBRARY_SEARCH = "https://openlibrary.org/search.json"
OPEN_LIBRARY_COVER = "https://covers.openlibrary.org/b/id/{cover_id}-L.jpg"

_TIMEOUT = httpx.Timeout(10.0, connect=5.0)
_HEADERS = {"User-Agent": "AnyShelf/1.0 (cover lookup; contact: support@anyshelf.app)"}
_MIN_IMAGE_BYTES = 1000  # Open Library serves a 1x1 GIF for covers it lacks


def _normalize(value: str) -> str:
    return re.sub(r"\s+", " ", (value or "").strip().lower())


async def fetch_cover(title: str, author: str) -> tuple[bytes, str] | None:
    """Look up a real cover for (title, author).

    Returns (image_bytes, content_type) on a confident match, or None if no
    match was found or every provider failed.
    """
    title = (title or "").strip()
    author = (author or "").strip()
    if not title:
        return None

    async with httpx.AsyncClient(timeout=_TIMEOUT, headers=_HEADERS, follow_redirects=True) as client:
        for lookup in (_try_open_library, _try_google_books):
            try:
                result = await lookup(client, title, author)
            except httpx.HTTPError as exc:
                logger.info("%s failed for %r / %r: %s", lookup.__name__, title, author, exc)
                continue
            if result:
                return result
    return None


async def _fetch_cover_image(client: httpx.AsyncClient, url: str) -> tuple[bytes, str] | None:
    """Download a cover image, filtering out Open Library's blank 1x1 GIFs."""
    img_resp = await client.get(url)
    img_resp.raise_for_status()
    if len(img_resp.content) < _MIN_IMAGE_BYTES:
        return None
    return img_resp.content, img_resp.headers.get("content-type", "image/jpeg")


async def _try_open_library(
    client: httpx.AsyncClient, title: str, author: str
) -> tuple[bytes, str] | None:
    # Full-text search finds real editions with covers, where the fielded
    # `title=` query often returns bare, coverless text editions. Search the
    # title alone first: appending the author as a phrase zeroes out results
    # whenever the typed author name doesn't tokenize-match the index (e.g.
    # "R.K. Rowling" vs "J. K. Rowling"), which is a common upload typo.
    # Fall back to the combined phrase only if the title search found nothing.
    for params in (
        {"q": f'"{title}"', "limit": 10},
        {"q": f"{title} {author}".strip(), "limit": 10},
    ):
        resp = await client.get(OPEN_LIBRARY_SEARCH, params=params)
        resp.raise_for_status()
        docs = resp.json().get("docs") or []
        if not docs:
            continue

        want = _normalize(title)

        def match_rank(doc: dict) -> int:
            doc_title = _normalize(doc.get("title") or "")
            if doc_title == want:
                return 0
            if want and want in doc_title:
                return 1
            return 2

        # Prefer editions whose title actually matches (avoids wrong-language
        # or unrelated hits like "Das Schloss" for an English "The Castle").
        for doc in sorted(docs, key=match_rank):
            cover_id = doc.get("cover_i")
            if not cover_id:
                continue
            result = await _fetch_cover_image(
                client, OPEN_LIBRARY_COVER.format(cover_id=cover_id)
            )
            if result:
                return result
    return None


async def _try_google_books(
    client: httpx.AsyncClient, title: str, author: str
) -> tuple[bytes, str] | None:
    query = f'intitle:"{title}"' + (f' inauthor:"{author}"' if author else "")
    resp = None
    for attempt in range(2):  # Google throttles keyless callers; retry once
        resp = await client.get(GOOGLE_BOOKS_API, params={"q": query, "maxResults": 1})
        if resp.status_code in (429, 500, 502, 503, 504):
            await asyncio.sleep(1.0 + attempt)
            continue
        break
    if resp is None or resp.status_code in (429, 500, 502, 503, 504):
        return None
    resp.raise_for_status()
    items = resp.json().get("items") or []
    if not items:
        return None

    image_links = items[0].get("volumeInfo", {}).get("imageLinks") or {}
    # Prefer the larger size when Google Books happens to offer one.
    cover_url = image_links.get("thumbnail") or image_links.get("smallThumbnail")
    if not cover_url:
        return None

    cover_url = cover_url.replace("http://", "https://")
    return await _fetch_cover_image(client, cover_url)
