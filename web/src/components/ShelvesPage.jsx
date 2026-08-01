import React, { useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Sidebar from "./Sidebar";
import { api } from "../api";
import AppHeader from "./AppHeader";
import { Modal, coverStyle, COLOR_PALETTE } from "./ShelfForm";
import { SHELVES_CHANGED, useShelfModal } from "./ShelfModalContext";

const PAGE_BANNERS = [
  "linear-gradient(120deg, #154212 0%, #2d5a27 45%, #a1d494 100%)",
  "linear-gradient(120deg, #283593 0%, #5c6bc0 50%, #a1d494 100%)",
  "linear-gradient(120deg, #4e342e 0%, #8d6e63 55%, #eae2ce 100%)",
  "linear-gradient(120deg, #8e24aa 0%, #c2185b 50%, #ffb6c1 100%)",
];

const BANNER_COLORS = [...PAGE_BANNERS, ...COLOR_PALETTE];

function timeAgo(dateStr) {
  if (!dateStr) return "recently";
  const t = new Date(dateStr).getTime();
  if (Number.isNaN(t)) return "recently";
  const diff = Math.max(0, Date.now() - t);
  const min = Math.floor(diff / 60000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  if (d < 7) return `${d}d ago`;
  const w = Math.floor(d / 7);
  if (w < 5) return `${w}w ago`;
  return new Date(dateStr).toLocaleDateString();
}

function ShelfDetail({ shelf, books, onClose, onEdit, onDelete, onChanged }) {
  const [allBooks, setAllBooks] = useState(null);

  useEffect(() => {
    api(`/shelves/${shelf.id}`).then((d) => setAllBooks(d.books)).catch(() => setAllBooks([]));
  }, [shelf.id]);

  const toggleBook = async (bookId, add) => {
    try {
      await api(`/shelves/${shelf.id}/books/${bookId}`, { method: add ? "POST" : "DELETE" });
      setAllBooks((prev) =>
        add
          ? [...(prev || []), books.find((b) => b.id === bookId)].filter(Boolean)
          : (prev || []).filter((b) => b.id !== bookId)
      );
      onChanged();
    } catch {}
  };

  return (
    <Modal onClose={onClose} width={640}>
      <div
        style={{
          ...coverStyle(shelf),
          height: 170,
          borderRadius: 22,
          margin: 0,
          position: "relative",
          display: "flex",
          alignItems: "flex-end",
          padding: 20,
        }}
      >
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(to top, rgba(0,0,0,0.55), rgba(0,0,0,0) 60%)" }} />
        <div style={{ position: "relative" }}>
          <div style={{ fontSize: 24, fontWeight: 700, color: "#fff", fontFamily: "var(--font-display)", textShadow: "0 1px 6px rgba(0,0,0,0.4)" }}>{shelf.name}</div>
          <div style={{ fontSize: 13, color: "rgba(255,255,255,0.92)", marginTop: 2 }}>
            {shelf.book_count} {shelf.book_count === 1 ? "book" : "books"}
          </div>
        </div>
        <div style={{ marginLeft: "auto", display: "flex", gap: 8, position: "relative" }}>
          <button
            className="btn"
            onClick={() => onEdit(allBooks || [])}
            style={{ fontSize: 13, background: "rgba(255,255,255,0.2)", color: "#fff", border: "1px solid rgba(255,255,255,0.4)", padding: "8px 14px", backdropFilter: "blur(6px)" }}
          >
            <span className="icon" style={{ fontSize: 16 }}>edit</span>
            Edit
          </button>
          <button
            className="btn"
            onClick={onDelete}
            style={{ fontSize: 13, background: "rgba(255,255,255,0.2)", color: "#fff", border: "1px solid rgba(255,255,255,0.4)", padding: "8px 14px", backdropFilter: "blur(6px)" }}
          >
            <span className="icon" style={{ fontSize: 16 }}>delete</span>
          </button>
          <button className="btn-icon" onClick={onClose} title="Close" style={{ background: "rgba(255,255,255,0.2)", color: "#fff" }}>
            <span className="icon">close</span>
          </button>
        </div>
      </div>

      <div className="shelf-detail__body">
        {shelf.description && <p className="text-muted" style={{ margin: 0, fontSize: 14 }}>{shelf.description}</p>}

        <div className="field">
          <label>Books in this shelf</label>
          <div className="book-picker" style={{ maxHeight: 220 }}>
            {(allBooks || []).length === 0 ? (
              <div className="text-muted" style={{ padding: 12, fontSize: 13 }}>No books in this shelf yet.</div>
            ) : (
              allBooks.map((b) => (
                <div key={b.id} className="book-row" style={{ cursor: "default" }}>
                  <span className="book-row__thumb">
                    <span className="icon" style={{ fontSize: 16 }}>auto_stories</span>
                  </span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <Link to={`/read/${b.id}`} className="book-row__title" style={{ display: "block" }}>
                      {b.title}
                    </Link>
                    <div className="text-muted" style={{ fontSize: 12 }}>
                      {b.extraction_status === "failed"
                        ? "Extraction failed"
                        : b.extraction_status === "done"
                        ? null
                        : "Extracting…"}
                    </div>
                  </div>
                  <button className="btn-icon" title="Remove" onClick={() => toggleBook(b.id, false)}>
                    <span className="icon" style={{ fontSize: 18 }}>close</span>
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}

export default function ShelvesPage() {
  const [shelves, setShelves] = useState([]);
  const [books, setBooks] = useState([]);
  const [detail, setDetail] = useState(null);
  const [pageBanner, setPageBanner] = useState(null);
  const [bannerColor, setBannerColor] = useState(null);
  const [uploading, setUploading] = useState(false);
  const bannerRef = useRef(null);
  const { openCreateShelf, openEditShelf } = useShelfModal();

  const load = async () => {
    const [s, b] = await Promise.all([api("/shelves/").catch(() => []), api("/books/").catch(() => [])]);
    setShelves(s);
    setBooks(b);
    return s;
  };

  const notifyChanged = () => {
    window.dispatchEvent(new CustomEvent(SHELVES_CHANGED));
  };

  useEffect(() => {
    api("/auth/me")
      .then((m) => setPageBanner(m.banner_url || null))
      .catch(() => {});
    const saved = localStorage.getItem("cloudread_page_banner_color");
    if (saved) setBannerColor(saved);
  }, []);

  const cycleBannerColor = () => {
    setBannerColor((prev) => {
      const idx = prev ? BANNER_COLORS.indexOf(prev) : 0;
      const next = BANNER_COLORS[(idx + 1) % BANNER_COLORS.length];
      localStorage.setItem("cloudread_page_banner_color", next);
      return next;
    });
  };

  const onBannerFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || uploading) return;
    setUploading(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const r = await api("/auth/me/banner", { method: "POST", formData: fd });
      setPageBanner(r.banner_url);
    } catch {
      alert("Could not upload the banner image.");
    } finally {
      setUploading(false);
    }
  };

  const removeBanner = async () => {
    try {
      await api("/auth/me/banner", { method: "DELETE" });
      setPageBanner(null);
    } catch {}
  };

  const [searchParams] = useSearchParams();

  useEffect(() => {
    (async () => {
      const s = await load();
      const id = searchParams.get("shelf");
      if (id) {
        const match = s.find((x) => x.id === id);
        if (match) setDetail(match);
      }
    })();
  }, []);

  useEffect(() => {
    const onChanged = () => load();
    window.addEventListener(SHELVES_CHANGED, onChanged);
    return () => window.removeEventListener(SHELVES_CHANGED, onChanged);
  }, []);

  const handleDelete = async (shelf) => {
    if (!window.confirm(`Delete the shelf "${shelf.name}"?`)) return;
    await api(`/shelves/${shelf.id}`, { method: "DELETE" });
    setDetail(null);
    notifyChanged();
    await load();
  };

  const totalBooks = books.length;

  return (
    <div style={{ minHeight: "100vh" }}>
      <Sidebar />

      <AppHeader title="Shelves" />

      <main className="main-desktop" style={{ paddingTop: 24, paddingRight: 24, paddingBottom: 120 }}>
        {/* Page banner */}
        <div
          style={{
            marginTop: 24,
            height: 200,
            borderRadius: 16,
            overflow: "hidden",
            position: "relative",
            background: pageBanner
              ? `url(${pageBanner}) center / cover no-repeat`
              : bannerColor || PAGE_BANNERS[0],
            display: "flex",
            alignItems: "flex-end",
            padding: 28,
            color: "#fff",
          }}
        >
          <div style={{ position: "absolute", inset: 0, background: "linear-gradient(to top, rgba(0,0,0,0.4), rgba(0,0,0,0) 60%)" }} />
          <div style={{ position: "absolute", right: -40, top: -40, width: 220, height: 220, background: "rgba(255,255,255,0.12)", borderRadius: "50%" }} />
          <div style={{ position: "relative" }}>
            <h1 style={{ fontFamily: "var(--font-display)", fontSize: 34, margin: 0, textShadow: "0 1px 4px rgba(0,0,0,0.3)" }}>My Shelves</h1>
            <p style={{ margin: "6px 0 0", fontSize: 15, opacity: 0.92 }}>
              {shelves.length} {shelves.length === 1 ? "shelf" : "shelves"} · {totalBooks} {totalBooks === 1 ? "book" : "books"} total
            </p>
          </div>
          <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 8, position: "relative" }}>
            <input
              ref={bannerRef}
              id="page-banner-input"
              type="file"
              accept="image/*"
              style={{ display: "none" }}
              onChange={onBannerFile}
            />
            <button
              className="btn"
              onClick={cycleBannerColor}
              title="Change banner colour"
              disabled={!!pageBanner}
              style={{
                background: "rgba(255,255,255,0.2)",
                color: "#fff",
                border: "1px solid rgba(255,255,255,0.35)",
                fontSize: 13,
                padding: "8px 14px",
                backdropFilter: "blur(6px)",
                opacity: pageBanner ? 0.5 : 1,
              }}
            >
              <span className="icon" style={{ fontSize: 16 }}>palette</span>
            </button>
            <button
              className="btn"
              onClick={() => bannerRef.current?.click()}
              disabled={uploading}
              style={{
                background: "rgba(255,255,255,0.2)",
                color: "#fff",
                border: "1px solid rgba(255,255,255,0.35)",
                fontSize: 13,
                padding: "8px 16px",
                backdropFilter: "blur(6px)",
              }}
            >
              <span className="icon" style={{ fontSize: 16 }}>photo_camera</span>
              {uploading ? "Uploading…" : pageBanner ? "Change Banner" : "Add Banner"}
            </button>
            {pageBanner && (
              <button
                className="btn"
                onClick={removeBanner}
                title="Remove custom banner"
                style={{
                  background: "rgba(255,255,255,0.2)",
                  color: "#fff",
                  border: "1px solid rgba(255,255,255,0.35)",
                  fontSize: 13,
                  padding: "8px 14px",
                  backdropFilter: "blur(6px)",
                }}
              >
                <span className="icon" style={{ fontSize: 16 }}>close</span>
              </button>
            )}
          </div>
        </div>

        {/* Shelves grid */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", gap: 24, marginTop: 28 }}>
          <button
            onClick={openCreateShelf}
            style={{
              minHeight: 260,
              borderRadius: 14,
              border: "2px dashed var(--outline-variant)",
              background: "transparent",
              cursor: "pointer",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              gap: 10,
              color: "var(--on-surface-variant)",
              padding: 24,
            }}
          >
            <div style={{ width: 56, height: 56, borderRadius: "50%", background: "var(--surface-container-high)", display: "flex", alignItems: "center", justifyContent: "center" }}>
              <span className="icon" style={{ fontSize: 28, color: "var(--primary)" }}>add</span>
            </div>
            <span style={{ fontSize: 15, fontWeight: 600, color: "var(--on-surface)" }}>Create New Shelf</span>
            <span className="text-muted" style={{ fontSize: 13, textAlign: "center" }}>Organize your reading by theme, mood, or project</span>
          </button>

          {shelves.map((shelf) => (
            <div
              key={shelf.id}
              className="card"
              style={{
                cursor: "pointer",
                padding: 16,
                background: "var(--surface-container-low)",
                border: "1px solid transparent",
              }}
              onClick={() => setDetail(shelf)}
            >
              <div style={{ position: "relative", height: 170, marginBottom: 14 }}>
                <div
                  style={{
                    position: "absolute",
                    inset: 0,
                    borderRadius: 12,
                    background: (shelf.color || COLOR_PALETTE[0]) + "66",
                    border: "1px solid var(--outline-variant)",
                    transform: "translateY(-6px) rotate(-1.4deg)",
                    transition: "transform 0.3s",
                  }}
                />
                <div
                  style={{
                    position: "absolute",
                    inset: 0,
                    borderRadius: 12,
                    background: (shelf.color || COLOR_PALETTE[0]) + "33",
                    border: "1px solid var(--outline-variant)",
                    transform: "translateY(-3px) rotate(0.7deg)",
                    transition: "transform 0.3s",
                  }}
                />
                <div
                  style={{
                    position: "absolute",
                    inset: 0,
                    borderRadius: 12,
                    overflow: "hidden",
                    border: "1px solid var(--outline-variant)",
                    boxShadow: "0 6px 18px rgba(0,0,0,0.14)",
                    ...coverStyle(shelf),
                  }}
                >
                  <div style={{ position: "absolute", inset: 0, background: "linear-gradient(to top, rgba(0,0,0,0.35), rgba(0,0,0,0) 45%)" }} />
                  <span
                    style={{
                      position: "absolute",
                      bottom: 10,
                      left: 10,
                      background: "rgba(255,255,255,0.92)",
                      color: "#1b1c1c",
                      borderRadius: 999,
                      padding: "3px 10px",
                      fontSize: 12,
                      fontWeight: 600,
                    }}
                  >
                    {shelf.name}
                  </span>
                </div>
              </div>
              <h3 style={{ fontFamily: "var(--font-ui)", fontSize: 16, fontWeight: 600, margin: 0 }}>{shelf.name}</h3>
              <div className="text-muted" style={{ fontSize: 13, marginTop: 4 }}>
                {shelf.book_count} {shelf.book_count === 1 ? "book" : "books"} · updated {timeAgo(shelf.created_at)}
              </div>
            </div>
          ))}
        </div>
      </main>

      {detail && (
        <ShelfDetail
          shelf={detail}
          books={books}
          onClose={() => setDetail(null)}
          onEdit={(bks) => {
            const d = detail;
            setDetail(null);
            openEditShelf({ ...d, books: bks });
          }}
          onDelete={() => handleDelete(detail)}
          onChanged={() => {
            notifyChanged();
            load();
          }}
        />
      )}
    </div>
  );
}
