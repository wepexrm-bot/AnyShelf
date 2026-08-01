import React, { useEffect, useState } from "react";
import { Link, useSearchParams, useLocation } from "react-router-dom";
import Sidebar from "./Sidebar";
import { api } from "../api";
import AppHeader from "./AppHeader";
import UploadModal, { GENRES } from "./UploadModal";

const ACCENTS = [
  "#154212",
  "#283593",
  "#8e24aa",
  "#c2185b",
  "#00695c",
  "#4e342e",
  "#546e7a",
  "#d84315",
];

function accentFor(book) {
  const s = (book.title || "") + (book.author || "");
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return ACCENTS[h % ACCENTS.length];
}

function formatAdded(createdAt) {
  if (!createdAt) return "—";
  const d = new Date(createdAt);
  if (isNaN(d.getTime())) return "—";
  return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function searchableText(book) {
  const date = book.created_at ? new Date(book.created_at) : null;
  const dateStr = date && !isNaN(date.getTime()) ? date.toLocaleDateString() : "";
  return `${book.title} ${book.author || ""} ${book.genre || ""} ${dateStr} ${book.created_at || ""}`.toLowerCase();
}

function BookCard({ book }) {
  const accent = accentFor(book);
  const location = useLocation();
  return (
    <div className="book-card">
      <Link
        to={`/read/${book.id}`}
        state={{ from: location.pathname }}
        className="book-card__cover"
        style={
          book.cover_url
            ? { backgroundImage: `url(${book.cover_url})`, backgroundSize: "cover", backgroundPosition: "center" }
            : { background: `linear-gradient(155deg, ${accent} 0%, ${accent}99 55%, #0d0f0d 135%)` }
        }
      >
        {!book.cover_url && (
          <div className="book-card__placeholder">
            <span className="icon" style={{ fontSize: 26 }}>auto_stories</span>
            <div className="book-card__placeholder-title">{book.title}</div>
          </div>
        )}
        <div className="book-card__hover">
          <div className="book-card__hover-row">
            <span className="book-card__hover-label">Author</span>
            <span>{book.author || "Unknown author"}</span>
          </div>
          <div className="book-card__hover-row">
            <span className="book-card__hover-label">Added</span>
            <span>{formatAdded(book.created_at)}</span>
          </div>
          <div className="book-card__hover-row">
            <span className="book-card__hover-label">Genre</span>
            <span>{book.genre || "—"}</span>
          </div>
        </div>
      </Link>
      <div className="book-card__title">{book.title}</div>
    </div>
  );
}

export default function BooksPage() {
  const [books, setBooks] = useState([]);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [genreFilter, setGenreFilter] = useState("");
  const [sort, setSort] = useState("newest");
  const [searchParams] = useSearchParams();
  const q = (searchParams.get("q") || "").trim().toLowerCase();
  const tokens = q.split(/\s+/).filter(Boolean);

  const load = async () => {
    setBooks(await api("/books/").catch(() => []));
  };

  useEffect(() => {
    load();
  }, []);

  let filtered = books.filter(
    (b) =>
      tokens.every((t) => searchableText(b).includes(t)) &&
      (!genreFilter || (b.genre || "") === genreFilter)
  );
  filtered = [...filtered].sort((a, b) => {
    const ta = a.created_at ? new Date(a.created_at).getTime() : 0;
    const tb = b.created_at ? new Date(b.created_at).getTime() : 0;
    return sort === "oldest" ? ta - tb : tb - ta;
  });

  const hasActiveFilters = !!(q || genreFilter || sort !== "newest");
  const clearFilters = () => {
    setGenreFilter("");
    setSort("newest");
  };

  return (
    <div style={{ minHeight: "100vh" }}>
      <Sidebar />

      <AppHeader title="Books">
        <button
          className="btn btn-primary"
          style={{ cursor: "pointer", margin: 0, display: "flex", alignItems: "center", gap: 8 }}
          onClick={() => setUploadOpen(true)}
        >
          <span className="icon" style={{ fontSize: 18 }}>upload_file</span>
          Upload PDF
        </button>
      </AppHeader>

      <main className="main-desktop" style={{ paddingTop: 32, paddingBottom: 64, paddingRight: 24 }}>
        <div style={{ width: "100%" }}>
          <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginBottom: 24 }}>
            <h2
              style={{
                fontFamily: "var(--font-display)",
                fontSize: 22,
                color: "var(--on-surface)",
                margin: 0,
              }}
            >
              Books
            </h2>
            <span className="text-muted" style={{ fontSize: 14 }}>
              {filtered.length} {filtered.length === 1 ? "book" : "books"}
            </span>
          </div>

          <div className="filter-bar">
            <div className="filter-group">
              <label className="filter-label" htmlFor="filter-genre">Genre</label>
              <div className="filter-select">
                <span className="icon filter-select__icon">category</span>
                <select
                  id="filter-genre"
                  value={genreFilter}
                  onChange={(e) => setGenreFilter(e.target.value)}
                >
                  <option value="">All genres</option>
                  {GENRES.map((g) => (
                    <option key={g} value={g}>{g}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="filter-group">
              <label className="filter-label" htmlFor="filter-sort">Sort by</label>
              <div className="filter-select">
                <span className="icon filter-select__icon">schedule</span>
                <select
                  id="filter-sort"
                  value={sort}
                  onChange={(e) => setSort(e.target.value)}
                >
                  <option value="newest">Newest added</option>
                  <option value="oldest">Oldest added</option>
                </select>
              </div>
            </div>

            {hasActiveFilters && (
              <button className="btn btn-ghost filter-clear" onClick={clearFilters}>
                <span className="icon" style={{ fontSize: 16 }}>close</span>
                Clear filters
              </button>
            )}
          </div>

          {filtered.length === 0 ? (
            <div className="card" style={{ padding: "48px 32px", textAlign: "center" }}>
              <span className="icon" style={{ fontSize: 40, color: "var(--on-surface-variant)", display: "block", marginBottom: 12 }}>
                auto_stories
              </span>
              <p className="text-muted" style={{ margin: 0, fontSize: 15 }}>
                {books.length === 0
                  ? "No books yet. Upload a PDF to get started."
                  : "No books match your filters."}
              </p>
            </div>
          ) : (
            <div className="books-grid">
              {filtered.map((book) => (
                <BookCard key={book.id} book={book} />
              ))}
            </div>
          )}
        </div>
      </main>

      {uploadOpen && (
        <UploadModal
          onClose={() => setUploadOpen(false)}
          onUploaded={async () => {
            setUploadOpen(false);
            await load();
          }}
        />
      )}
    </div>
  );
}
