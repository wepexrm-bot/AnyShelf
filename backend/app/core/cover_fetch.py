"""Automatic book-cover lookup by title/author.

No AI image generation and no placeholder art here -- this only returns a
cover when a real published edition is actually found. If nothing matches,
callers should leave the book without a cover rather than substituting
anything synthetic.

Tries, in order:
  1. Google Books API (best hit rate, no key required for basic search)
  2. Open Library (fallback, also keyless)

Both calls are best-effort: network errors, rate limits, or no-match results
are all treated the same way -- log and return None. A cover lookup failing
should never fail the book upload itself.
"""

from __future__ import annotations

import logging

import httpx

logger = logging.getLogger("cloudread.cover_fetch")

GOOGLE_BOOKS_API = "https://www.googleapis.com/books/v1/volumes"
OPEN_LIBRARY_SEARCH = "https://openlibrary.org/search.json"
OPEN_LIBRARY_COVER = "https://covers.openlibrary.org/b/id/{cover_id}-L.jpg"

_TIMEOUT = httpx.Timeout(6.0, connect=3.0)
_HEADERS = {"User-Agent": "AnyShelf/1.0 (cover lookup; contact: support@anyshelf.app)"}


async def fetch_cover(title: str, author: str) -> tuple[bytes, str] | None:
    """Look up a real cover for (title, author).

    Returns (image_bytes, content_type) on a confident match, or None if no
    match was found or every provider failed.
    """
    title = (title or "").strip()
    author = (author or "").strip()
    if not title:
        return None

    async with httpx.AsyncClient(timeout=_TIMEOUT, headers=_HEADERS) as client:
        for lookup in (_try_google_books, _try_open_library):
            try:
                result = await lookup(client, title, author)
            except httpx.HTTPError as exc:
                logger.info("%s failed for %r / %r: %s", lookup.__name__, title, author, exc)
                continue
            if result:
                return result
    return None


async def _try_google_books(
    client: httpx.AsyncClient, title: str, author: str
) -> tuple[bytes, str] | None:
    query = f'intitle:"{title}"' + (f' inauthor:"{author}"' if author else "")
    resp = await client.get(GOOGLE_BOOKS_API, params={"q": query, "maxResults": 1})
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
    img_resp = await client.get(cover_url)
    img_resp.raise_for_status()
    return img_resp.content, img_resp.headers.get("content-type", "image/jpeg")


async def _try_open_library(
    client: httpx.AsyncClient, title: str, author: str
) -> tuple[bytes, str] | None:
    params = {"title": title, "limit": 1}
    if author:
        params["author"] = author
    resp = await client.get(OPEN_LIBRARY_SEARCH, params=params)
    resp.raise_for_status()
    docs = resp.json().get("docs") or []
    if not docs:
        return None

    cover_id = docs[0].get("cover_i")
    if not cover_id:
        return None

    img_resp = await client.get(OPEN_LIBRARY_COVER.format(cover_id=cover_id))
    img_resp.raise_for_status()
    # Open Library serves a tiny 1x1 GIF for editions with no real cover
    # image instead of a 404 -- filter those out rather than storing them.
    if len(img_resp.content) < 1000:
        return None
    return img_resp.content, img_resp.headers.get("content-type", "image/jpeg")
