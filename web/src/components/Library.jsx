import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams, useLocation } from "react-router-dom";
import Sidebar from "./Sidebar";
import { api } from "../api";
import AppHeader from "./AppHeader";
import ContinueReadingCarousel from "./ContinueReadingCarousel";
import { SHELVES_CHANGED, useShelfModal } from "./ShelfModalContext";
import { coverStyle } from "./ShelfForm";
import UploadModal from "./UploadModal";

const BOOK_ACCENTS = [
  "#154212",
  "#283593",
  "#8e24aa",
  "#c2185b",
  "#00695c",
  "#4e342e",
  "#546e7a",
  "#d84315",
];

export function bookAccent(book) {
  const s = (book.title || "") + (book.author || "");
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return BOOK_ACCENTS[h % BOOK_ACCENTS.length];
}

function hexToRgb(hex) {
  const cleaned = (hex || "#000000").replace("#", "");
  const full = cleaned.length === 3 ? cleaned.split("").map((c) => c + c).join("") : cleaned;
  const num = parseInt(full, 16);
  return { r: (num >> 16) & 255, g: (num >> 8) & 255, b: num & 255 };
}

export function ensureReadable(hex) {
  const { r, g, b } = hexToRgb(hex);
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  if (lum < 0.5) return hex;
  const f = 0.38;
  return "#" + [r, g, b].map((v) => Math.round(v * f).toString(16).padStart(2, "0")).join("");
}

export function useImageAccent(src, fallback) {
  const [accent, setAccent] = useState(null);
  useEffect(() => {
    let cancelled = false;
    if (!src) {
      setAccent(null);
      return;
    }
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      try {
        const w = 60;
        const h = 80;
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, w, h);
        const data = ctx.getImageData(0, 0, w, h).data;
        let r = 0, g = 0, b = 0, n = 0;
        for (let i = 0; i < data.length; i += 4) {
          if (data[i + 3] === 0) continue;
          r += data[i];
          g += data[i + 1];
          b += data[i + 2];
          n++;
        }
        if (n > 0) {
          const c = "#" + [Math.round(r / n), Math.round(g / n), Math.round(b / n)]
            .map((v) => v.toString(16).padStart(2, "0"))
            .join("");
          if (!cancelled) setAccent(c);
        }
      } catch {
        if (!cancelled) setAccent(null);
      }
    };
    img.onerror = () => {
      if (!cancelled) setAccent(null);
    };
    img.src = src;
    return () => {
      cancelled = true;
    };
  }, [src]);
  return accent || fallback;
}

function ProgressBar({ value }) {
  return (
    <div className="progress-track">
      <div className="progress-fill" style={{ width: `${Math.max(0, Math.min(100, value))}%` }} />
    </div>
  );
}

export default function Library() {
  const { openCreateShelf } = useShelfModal();
  const location = useLocation();
  const [books, setBooks] = useState([]);
  const [shelves, setShelves] = useState([]);
  const [stats, setStats] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [pendingUpload, setPendingUpload] = useState(null);
  const [searchParams] = useSearchParams();
  const [bookProgress, setBookProgress] = useState({});
  const [shelfNames, setShelfNames] = useState({});
  const [extracting, setExtracting] = useState({});
  const timersRef = useRef(new Map());

  const stopPolling = (bookId) => {
    const t = timersRef.current.get(bookId);
    if (t) clearInterval(t);
    timersRef.current.delete(bookId);
  };

  const startPolling = (bookId) => {
    if (timersRef.current.has(bookId)) return;
    setExtracting((e) => ({ ...e, [bookId]: { status: "pending", progress: 0 } }));
    const timer = setInterval(async () => {
      try {
        const r = await api(`/books/${bookId}/progress`);
        setExtracting((e) => ({ ...e, [bookId]: { status: r.extraction_status, progress: r.progress } }));
        if (r.extraction_status === "done" || r.extraction_status === "failed") {
          stopPolling(bookId);
          await loadAll();
        }
      } catch {
        stopPolling(bookId);
      }
    }, 700);
    timersRef.current.set(bookId, timer);
  };

  useEffect(
    () => () => {
      timersRef.current.forEach((t) => clearInterval(t));
      timersRef.current.clear();
    },
    []
  );

  const loadAll = async () => {
    const [b, s, st] = await Promise.all([
      api("/books/").catch(() => []),
      api("/shelves/").catch(() => []),
      api("/stats/").catch(() => null),
    ]);
    setBooks(b);
    setShelves(s);
    setStats(st);

    for (const book of b) {
      if (book.extraction_status === "pending" || book.extraction_status === "processing") {
        startPolling(book.id);
      }
    }

    const names = {};
    for (const shelf of s) names[shelf.id] = shelf.name;
    setShelfNames(names);

    const progress = {};
    await Promise.all(
      b.map(async (book) => {
        try {
          const p = await api(`/sync/progress/${book.id}`);
          progress[book.id] = p.current_page || 0;
        } catch {
          progress[book.id] = 0;
        }
      })
    );
    setBookProgress(progress);
  };

  useEffect(() => {
    loadAll();
  }, []);

  useEffect(() => {
    const onChanged = () => loadAll();
    window.addEventListener(SHELVES_CHANGED, onChanged);
    return () => window.removeEventListener(SHELVES_CHANGED, onChanged);
  }, []);

  const handleDelete = async (bookId) => {
    if (!window.confirm("Delete this book permanently?")) return;
    await api(`/books/${bookId}`, { method: "DELETE" });
    await loadAll();
  };

  const [menuFor, setMenuFor] = useState(null);
  const menuRef = useRef(null);

  useEffect(() => {
    const onClick = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) setMenuFor(null);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const toggleInShelf = async (bookId, shelfId) => {
    const shelf = shelves.find((s) => s.id === shelfId);
    const inShelf = shelf?.book_ids?.includes(bookId);
    try {
      if (inShelf) {
        await api(`/shelves/${shelfId}/books/${bookId}`, { method: "DELETE" });
      } else {
        await api(`/shelves/${shelfId}/books/${bookId}`, { method: "POST" });
      }
      await loadAll();
    } catch {}
  };

  const query = searchParams.get("q") || "";
  const filtered = books.filter((b) =>
    `${b.title} ${b.author || ""}`.toLowerCase().includes(query.toLowerCase())
  );

  const isCompleted = (b) => (bookProgress[b.id] || 0) >= 99.5;

  const resumeBooks = useMemo(
    () => books.filter((b) => !isCompleted(b) && (bookProgress[b.id] || 0) > 0),
    [books, bookProgress]
  );
  const recentlyAdded = filtered.slice(0, 3);
  const extractionFor = (book) =>
    extracting[book.id] || { status: book.extraction_status, progress: 0 };

  return (
    <div style={{ minHeight: "100vh" }}>
      <Sidebar />

      <AppHeader title="Library">
        <button
          className="btn btn-primary"
          style={{ cursor: "pointer", margin: 0, display: "flex", alignItems: "center", gap: 8 }}
          onClick={() => setPendingUpload({})}
        >
          <span className="icon" style={{ fontSize: 18 }}>upload_file</span>
          Upload PDF
        </button>
      </AppHeader>

      <main className="main-desktop" style={{ paddingTop: 32, paddingBottom: 64, paddingRight: 24 }}>
        <div style={{ width: "100%", display: "flex", flexDirection: "column", gap: 48 }}>
          {/* Continue Reading carousel */}
          <ContinueReadingCarousel
            books={resumeBooks}
            bookProgress={bookProgress}
            extractionFor={extractionFor}
            location={location}
          />
          {/* Bento: shelves + stats */}
          <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 24 }}>
            <section>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 24 }}>
                <h2
                  style={{
                    fontFamily: "var(--font-display)",
                    fontSize: 18,
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                  }}
                >
                  <span className="icon text-primary" style={{ fontSize: 20 }}>shelves</span>
                  My Shelves
                </h2>
              </div>

              {shelves.length === 0 ? (
                <div className="card" style={{ padding: 24, color: "var(--on-surface-variant)" }}>
                  No shelves yet. Shelves help you organize your library into groups.
                </div>
              ) : (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 16 }}>
                  {shelves.map((shelf) => (
                    <Link
                      key={shelf.id}
                      to={`/shelves?shelf=${shelf.id}`}
                      className="card shelf-card-link"
                      style={{
                        padding: 12,
                        background: "var(--surface-container-low)",
                        border: "1px solid transparent",
                      }}
                    >
                      <div
                        style={{
                          position: "relative",
                          width: "100%",
                          aspectRatio: "5 / 3",
                          borderRadius: 12,
                          overflow: "hidden",
                          border: "1px solid var(--outline-variant)",
                          boxShadow: "0 4px 14px rgba(0,0,0,0.12)",
                          ...coverStyle(shelf),
                        }}
                      >
                        <div
                          style={{
                            position: "absolute",
                            inset: 0,
                            background: "linear-gradient(to top, rgba(0,0,0,0.45), rgba(0,0,0,0) 55%)",
                          }}
                        />
                        <span
                          style={{
                            position: "absolute",
                            bottom: 8,
                            left: 8,
                            maxWidth: "70%",
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
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
                        <span
                          style={{
                            position: "absolute",
                            top: 8,
                            right: 8,
                            background: "rgba(0,0,0,0.45)",
                            color: "#fff",
                            borderRadius: 999,
                            padding: "2px 9px",
                            fontSize: 11,
                            fontWeight: 600,
                            backdropFilter: "blur(4px)",
                          }}
                        >
                          {shelf.book_count}
                        </span>
                      </div>
                      <h3
                        style={{
                          fontFamily: "var(--font-ui)",
                          fontSize: 15,
                          fontWeight: 600,
                          margin: "12px 2px 2px",
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {shelf.name}
                      </h3>
                      <div
                        className="text-muted"
                        style={{
                          fontSize: 12,
                          margin: "0 2px",
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {shelf.book_count} {shelf.book_count === 1 ? "book" : "books"}
                        {shelf.description ? ` · ${shelf.description}` : ""}
                      </div>
                    </Link>
                  ))}
                </div>
              )}
            </section>

            {/* Stats card */}
            <section>
              <div
                style={{
                  height: "100%",
                  minHeight: 220,
                  borderRadius: 12,
                  background: "linear-gradient(135deg, var(--primary-container), var(--primary))",
                  color: "var(--on-primary-container)",
                  padding: 24,
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "space-between",
                  position: "relative",
                  overflow: "hidden",
                }}
              >
                <div style={{ position: "absolute", right: -30, top: -30, width: 160, height: 160, background: "rgba(255,255,255,0.1)", borderRadius: "50%" }} />
                <div>
                  <h3 style={{ fontFamily: "var(--font-ui)", fontSize: 12, textTransform: "uppercase", letterSpacing: 2, color: "var(--primary-fixed-dim, #bcf0ae)", marginBottom: 8 }}>
                    This Month
                  </h3>
                  <div style={{ fontFamily: "var(--font-display)", fontSize: 56, lineHeight: 1, color: "#fff" }}>
                    {stats?.books_completed ?? 0}
                  </div>
                  <p style={{ margin: "8px 0 0", fontSize: 15 }}>Books completed</p>
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                    <div style={{ width: 44, height: 44, borderRadius: 8, background: "rgba(0,0,0,0.2)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                      <span className="icon" style={{ fontSize: 20, color: "#fff" }}>timer</span>
                    </div>
                    <div>
                      <div style={{ fontWeight: 600, color: "#fff" }}>
                        {Math.round((stats?.total_reading_minutes ?? 0) / 60)} hrs
                      </div>
                      <div style={{ fontSize: 12, opacity: 0.85 }}>Reading time</div>
                    </div>
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                    <div style={{ width: 44, height: 44, borderRadius: 8, background: "rgba(0,0,0,0.2)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                      <span className="icon" style={{ fontSize: 20, color: "#fff" }}>local_fire_department</span>
                    </div>
                    <div>
                      <div style={{ fontWeight: 600, color: "#fff" }}>
                        {stats?.current_streak ?? 0} day{stats?.current_streak === 1 ? "" : "s"}
                      </div>
                      <div style={{ fontSize: 12, opacity: 0.85 }}>Reading streak</div>
                    </div>
                  </div>
                </div>
              </div>
            </section>
          </div>

          {/* Recently added list */}
          <section>
            <h2
              style={{
                fontFamily: "var(--font-display)",
                fontSize: 18,
                display: "flex",
                alignItems: "center",
                gap: 8,
                marginBottom: 24,
              }}
            >
              <span className="icon text-primary" style={{ fontSize: 20 }}>history</span>
              Recently Added
            </h2>

            {recentlyAdded.length === 0 ? (
              <div className="card" style={{ padding: 32, textAlign: "center", color: "var(--on-surface-variant)" }}>
                {uploading ? "Uploading…" : "Your library is empty. Upload a PDF to get started."}
              </div>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                {recentlyAdded.map((book) => (
                  <div
                    key={book.id}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 16,
                      padding: 12,
                      borderRadius: 8,
                      borderBottom: "1px solid var(--outline-variant)",
                    }}
                  >
                    <div
                      style={{
                        width: 48,
                        height: 64,
                        borderRadius: 4,
                        flexShrink: 0,
                        boxShadow: "0 1px 3px rgba(0,0,0,0.15)",
                        background: book.cover_url
                          ? `url(${book.cover_url}) center / cover no-repeat`
                          : "var(--tertiary-container)",
                        color: "var(--on-tertiary-container)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                      }}
                    >
                      {!book.cover_url && <span className="icon" style={{ fontSize: 20 }}>auto_stories</span>}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 2 }}>
                        <Link
                          to={`/read/${book.id}`}
                          state={{ from: location.pathname }}
                          style={{ fontWeight: 600, fontSize: 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", display: "block" }}
                        >
                          {book.title}
                        </Link>
                        {book.is_scanned && <span className="badge badge-secondary">scanned</span>}
                      </div>
                      <div className="text-muted" style={{ fontSize: 12 }}>
                        {book.extraction_status === "failed"
                          ? "Extraction failed"
                          : book.extraction_status === "done"
                          ? null
                          : `Extracting… ${extractionFor(book).progress}%`}
                      </div>
                    </div>
                    <div style={{ width: 120, flexShrink: 0 }}>
                      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "var(--on-surface-variant)", marginBottom: 4 }}>
                        <span>Progress</span>
                        <span>
                          {book.extraction_status === "failed"
                            ? "Failed"
                            : book.extraction_status === "done"
                            ? bookProgress[book.id] > 0
                              ? `${Math.round(bookProgress[book.id])}%`
                              : "0%"
                            : `${extractionFor(book).progress}%`}
                        </span>
                      </div>
                      <ProgressBar
                        value={
                          book.extraction_status === "done"
                            ? bookProgress[book.id]
                            : book.extraction_status === "failed"
                            ? 0
                            : extractionFor(book).progress
                        }
                      />
                    </div>
                    <div ref={menuRef} style={{ display: "flex", alignItems: "center", gap: 4, position: "relative" }}>
                      <button
                        className="btn-icon"
                        title="Add to shelf"
                        onClick={() => setMenuFor((p) => (p === book.id ? null : book.id))}
                      >
                        <span className="icon" style={{ fontSize: 20 }}>more_vert</span>
                      </button>
                      {menuFor === book.id && (
                        <div
                          className="card"
                          style={{
                            position: "absolute",
                            right: 0,
                            top: 42,
                            zIndex: 60,
                            width: 250,
                            padding: 8,
                            background: "var(--surface-container-lowest)",
                            boxShadow: "0 8px 24px rgba(0,0,0,0.18)",
                          }}
                        >
                          <div style={{ padding: "8px 12px 6px", fontSize: 12, textTransform: "uppercase", letterSpacing: 1, color: "var(--on-surface-variant)" }}>
                            Move to shelf
                          </div>
                          {shelves.length === 0 && (
                            <div className="text-muted" style={{ padding: "8px 12px", fontSize: 13 }}>
                              No shelves yet.
                            </div>
                          )}
                          {shelves.map((shelf) => {
                            const inShelf = shelf.book_ids?.includes(book.id);
                            return (
                              <button
                                key={shelf.id}
                                className="sidebar-link"
                                onClick={() => toggleInShelf(book.id, shelf.id)}
                                style={{
                                  display: "flex",
                                  alignItems: "center",
                                  gap: 10,
                                  width: "100%",
                                  padding: "8px 12px",
                                  fontSize: 14,
                                }}
                              >
                                <span
                                  style={{
                                    width: 14,
                                    height: 14,
                                    borderRadius: 4,
                                    flexShrink: 0,
                                    background: (shelf.color || "#154212") + (inShelf ? "" : "66"),
                                    border: "1px solid var(--outline-variant)",
                                  }}
                                />
                                <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{shelf.name}</span>
                                {inShelf && <span className="icon" style={{ fontSize: 16, color: "var(--primary)" }}>check</span>}
                              </button>
                            );
                          })}
                          <button
                            onClick={() => {
                              setMenuFor(null);
                              openCreateShelf();
                            }}
                            className="sidebar-link"
                            style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 12px", fontSize: 14, borderTop: "1px solid var(--outline-variant)", marginTop: 4, width: "100%", textAlign: "left" }}
                          >
                            <span className="icon" style={{ fontSize: 16 }}>add</span>
                            New shelf…
                          </button>
                        </div>
                      )}
                      <button className="btn-icon" title="Delete" onClick={() => handleDelete(book.id)}>
                        <span className="icon" style={{ fontSize: 20 }}>delete</span>
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </main>

      {pendingUpload && (
        <UploadModal
          file={pendingUpload.file}
          fileName={pendingUpload.fileName}
          onClose={() => setPendingUpload(null)}
          onUploaded={async (res) => {
            setPendingUpload(null);
            setUploading(true);
            await loadAll();
            setUploading(false);
            startPolling(res.book_id);
          }}
        />
      )}
    </div>
  );
}
