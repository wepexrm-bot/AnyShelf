import React, { useCallback, useEffect, useRef, useState } from "react";
import { useParams, useNavigate, useLocation } from "react-router-dom";
import ThemeControls, { FONT_OPTIONS, THEME_PRESETS } from "./ThemeControls";
import BookPaginate from "./BookPaginate";
import { api } from "../api";

const DEFAULT_THEME = {
  themeId: "light",
  customBackground: null,
  background: "#fcf9f8",
  textColor: "#1b1c1c",
  fontId: "serif",
  font: FONT_OPTIONS[0].stack,
  fontSize: 20,
  lineSpacing: 1.6,
  marginId: "medium",
  margins: 96,
  mode: "scroll",
  pageLayout: "spread",
};

function isDarkColor(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || "");
  if (!m) return false;
  const n = parseInt(m[1], 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return 0.299 * r + 0.587 * g + 0.114 * b < 128;
}

// The reader paints its own background/text from `theme`, so the app-wide
// CSS tokens (--surface-container-lowest, --on-surface, ...) must be
// overridden scoped to the reader to match the reader's theme. Without this,
// a light reader theme inside a dark-mode app would render dark surfaces
// with dark text (invisible content).
function readerThemeVars(theme) {
  let dark;
  if (theme.themeId === "dark" || theme.themeId === "night") dark = true;
  else if (theme.themeId === "custom") dark = isDarkColor(theme.customBackground || theme.background);
  else dark = false;

  if (dark) {
    return {
      "--surface": "#121412",
      "--surface-container-lowest": "#0d0f0d",
      "--surface-container-low": "#1a1c1a",
      "--surface-container": "#1e201e",
      "--surface-container-high": "#292a28",
      "--surface-variant": "#333533",
      "--on-surface": "#e2e3df",
      "--on-surface-variant": "#c2c9bb",
      "--outline": "#8c9387",
      "--outline-variant": "#42493e",
      "--primary": "#a1d494",
      "--on-primary": "#0a3909",
      "--surface-tint": "#a1d494",
    };
  }
  return {
    "--surface": "#fcf9f8",
    "--surface-container-lowest": "#ffffff",
    "--surface-container-low": "#f6f3f2",
    "--surface-container": "#f0eded",
    "--surface-container-high": "#eae7e7",
    "--surface-variant": "#e4e2e1",
    "--on-surface": "#1b1c1c",
    "--on-surface-variant": "#42493e",
    "--outline": "#72796e",
    "--outline-variant": "#c2c9bb",
    "--primary": "#154212",
    "--on-primary": "#ffffff",
    "--surface-tint": "#3b6934",
  };
}

export default function Reader() {
  const { bookId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const backTo = location.state?.from || "/";
  const [book, setBook] = useState(null);
  const [structuredText, setStructuredText] = useState(null);
  const [theme, setTheme] = useState(DEFAULT_THEME);
  const [panel, setPanel] = useState(null);
  const [annotations, setAnnotations] = useState([]);
  const [progress, setProgress] = useState(0);
  const [progressLoaded, setProgressLoaded] = useState(false);
  const [currentPage, setCurrentPage] = useState(0);
  const [pageCount, setPageCount] = useState(0);
  const scrollRef = useRef(null);
  const pageRefs = useRef([]);
  const [jumpValue, setJumpValue] = useState("1");
  const [jumpFocused, setJumpFocused] = useState(false);

  const handleBookPageChange = useCallback((idx, total) => {
    setCurrentPage(idx + 1);
    if (total > 0) setProgress(((idx + 1) / total) * 100);
  }, []);

  const jumpToPage = useCallback(
    (raw) => {
      const n = parseInt(raw, 10);
      if (!n || !pageCount) return;
      const clamped = Math.max(1, Math.min(pageCount, n));
      setJumpValue(String(clamped));
      const el = pageRefs.current[clamped - 1];
      const container = scrollRef.current;
      if (!el || !container) return;
      const cRect = container.getBoundingClientRect();
      const eRect = el.getBoundingClientRect();
      container.scrollTo({
        top: container.scrollTop + (eRect.top - cRect.top) - 48,
        behavior: "smooth",
      });
    },
    [pageCount]
  );

  useEffect(() => {
    if (!jumpFocused) setJumpValue(String(currentPage || 1));
  }, [currentPage, jumpFocused]);

  const currentAnchor = currentPage > 0 ? `Page ${Math.round(currentPage)}` : null;
  const activeBookmark = annotations.find((a) => a.kind === "bookmark" && a.anchor === currentAnchor);

  const refreshAnnotations = useCallback(async () => {
    try {
      setAnnotations(await api(`/sync/annotations/${bookId}`));
    } catch {}
  }, [bookId]);

  const toggleBookmark = useCallback(async () => {
    if (!currentAnchor) return;
    try {
      if (activeBookmark) {
        await api(`/sync/annotations/${activeBookmark.id}`, { method: "DELETE" });
      } else {
        await api("/sync/annotations", {
          method: "POST",
          body: { book_id: bookId, kind: "bookmark", anchor: currentAnchor },
        });
      }
      await refreshAnnotations();
    } catch (err) {
      alert(err.message);
    }
  }, [currentAnchor, activeBookmark, bookId, refreshAnnotations]);

  const switchMode = useCallback((mode) => {
    setTheme((t) => ({ ...t, mode }));
  }, []);

  // Persist reading-mode changes made from the header toggle
  useEffect(() => {
    if (!book) return;
    const timer = setTimeout(() => {
      api("/settings/", {
        method: "PUT",
        body: {
          theme: theme.themeId,
          custom_background: theme.customBackground || null,
          font_family: theme.fontId,
          font_size: theme.fontSize,
          line_spacing: theme.lineSpacing,
          margins: theme.marginId,
          reading_mode: theme.mode,
          page_layout: theme.pageLayout,
        },
      }).catch(() => {});
    }, 400);
    return () => clearTimeout(timer);
  }, [theme.mode, book]);

  useEffect(() => {
    (async () => {
      setBook(null);
      setStructuredText(null);
      setPageCount(0);
      setProgress(0);
      setProgressLoaded(false);
      setCurrentPage(0);
      setAnnotations([]);
      const data = await api(`/books/${bookId}`);
      setBook(data);
      if (data.structured_text_url) {
        const res = await fetch(data.structured_text_url);
        const st = await res.json();
        setStructuredText(st);
        setPageCount(st.pages?.length || 0);
      }

      const [savedSettings, savedProgress, savedAnnotations] = await Promise.all([
        api("/settings/").catch(() => null),
        api(`/sync/progress/${bookId}`).catch(() => null),
        api(`/sync/annotations/${bookId}`).catch(() => []),
      ]);

      if (savedSettings) {
        const preset = THEME_PRESETS.find((p) => p.id === savedSettings.theme) || THEME_PRESETS[0];
        const font = FONT_OPTIONS.find((f) => f.id === savedSettings.font_family) || FONT_OPTIONS[0];
        setTheme({
          themeId: savedSettings.theme,
          customBackground: savedSettings.custom_background || null,
          background: savedSettings.custom_background || preset.background,
          textColor: preset.textColor,
          fontId: font.id,
          font: font.stack,
          fontSize: savedSettings.font_size || 20,
          lineSpacing: savedSettings.line_spacing || 1.6,
          marginId: savedSettings.margins || "medium",
          margins:
            savedSettings.margins === "small"
              ? 48
              : savedSettings.margins === "large"
              ? 144
              : 96,
          mode: savedSettings.reading_mode || "scroll",
          pageLayout: savedSettings.page_layout || "spread",
        });
      }

      if (savedProgress) {
        const pc = savedProgress.current_page || 0;
        setProgress(pc);
      }
      setProgressLoaded(true);
      setAnnotations(savedAnnotations);
    })();
  }, [bookId]);

  // Track scroll depth -> reading progress + current page (scroll mode)
  useEffect(() => {
    if (theme.mode !== "scroll") return;
    const el = scrollRef.current;
    if (!el) return;
    const updateFromScroll = () => {
      const max = el.scrollHeight - el.clientHeight;
      if (max <= 0) return;
      const pct = Math.min(100, Math.max(0, (el.scrollTop / max) * 100));
      setProgress(pct);
      const containerTop = el.getBoundingClientRect().top;
      const readLine = containerTop + 80;
      let cur = 0;
      for (let i = 0; i < pageRefs.current.length; i++) {
        const p = pageRefs.current[i];
        if (!p) continue;
        if (p.getBoundingClientRect().top <= readLine) cur = i + 1;
      }
      if (cur > 0) setCurrentPage(cur);
    };
    el.addEventListener("scroll", updateFromScroll);
    return () => el.removeEventListener("scroll", updateFromScroll);
  }, [book, theme.mode]);

  // Resume at the current relative position whenever entering scroll mode,
  // but only after saved progress has actually loaded (otherwise it would
  // restore to 0% / page 1 before the server responds). Re-applies once
  // web fonts finish loading so a late reflow doesn't throw off the spot.
  // `progress` is intentionally NOT a dependency, so scrolling within scroll
  // mode never re-triggers a restore (which would fight the reader).
  const lastRestoreTopRef = useRef(-1);
  useEffect(() => {
    if (theme.mode !== "scroll" || !book || !structuredText || !progressLoaded) return;
    lastRestoreTopRef.current = -1;
    let cancelled = false;
    const restore = () => {
      if (cancelled) return;
      const el = scrollRef.current;
      if (!el) return;
      const max = el.scrollHeight - el.clientHeight;
      if (max <= 0) return;
      const pct = Math.min(100, Math.max(0, progress));
      const target = (pct / 100) * max;
      if (lastRestoreTopRef.current >= 0 && Math.abs(el.scrollTop - lastRestoreTopRef.current) > 50) {
        return; // user already scrolled away; don't fight them
      }
      el.scrollTop = target;
      lastRestoreTopRef.current = target;
    };
    restore();
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(restore);
    }
    return () => {
      cancelled = true;
    };
  }, [theme.mode, book, structuredText, progressLoaded]);

  // Sync progress + record session when scrolling settles
  useEffect(() => {
    if (!bookId || progress === 0) return;
    const timer = setTimeout(() => {
      api("/sync/progress", {
        method: "POST",
        body: { book_id: bookId, current_page: progress, current_offset: 0 },
      }).catch(() => {});
    }, 800);
    return () => clearTimeout(timer);
  }, [progress, bookId]);

  const secondsRef = useRef(0);
  const pagesRef = useRef(0);
  const lastPageRef = useRef(0);
  const progressRef = useRef(0);

  useEffect(() => {
    progressRef.current = progress;
  }, [progress]);

  const flushSession = useCallback(
    async (force) => {
      let minutes = Math.floor(secondsRef.current / 60);
      if (force && secondsRef.current % 60 >= 30) minutes += 1;
      const pages = pagesRef.current;
      secondsRef.current = 0;
      pagesRef.current = 0;
      if (minutes <= 0 && pages <= 0) return;
      try {
        await api("/stats/sessions", {
          method: "POST",
          body: {
            book_id: bookId,
            pages,
            minutes,
            finished: progressRef.current >= 100,
          },
        });
      } catch {}
    },
    [bookId]
  );

  useEffect(() => {
    const iv = setInterval(() => {
      if (document.hidden) return;
      secondsRef.current += 1;
      if (secondsRef.current >= 60) flushSession(false);
    }, 1000);
    return () => {
      clearInterval(iv);
      flushSession(true);
    };
  }, [flushSession]);

  useEffect(() => {
    if (currentPage > 0 && currentPage !== lastPageRef.current) {
      if (lastPageRef.current === 0) {
        lastPageRef.current = currentPage;
        return;
      }
      pagesRef.current += 1;
      lastPageRef.current = currentPage;
    }
  }, [currentPage]);

  if (!book) return <div className="loading">Loading bookâ€¦</div>;

  const reflowAvailable = book.reflow_confidence >= 0.5 && structuredText;
  const allBlocks = reflowAvailable
    ? structuredText.pages.flatMap((p) => p.blocks || [])
    : [];

  const readingStyle = {
    background: theme.background,
    color: theme.textColor,
  };

  return (
    <div
      style={{
        height: "100vh",
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
        background: theme.background,
        color: theme.textColor,
        fontFamily: theme.font,
        ...readerThemeVars(theme),
      }}
    >
      {/* Reading progress bar */}
      <div style={{ position: "fixed", top: 0, left: 0, right: 0, height: 3, background: "transparent", zIndex: 60 }}>
        <div style={{ height: "100%", background: "var(--primary)", width: `${progress}%`, transition: "width 0.2s ease-out" }} />
      </div>

      {/* Top nav */}
      <header
        style={{
          height: 56,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 24px",
          background: theme.themeId === "dark" || theme.themeId === "night" ? "rgba(27,27,31,0.9)" : "rgba(252,249,248,0.9)",
          backdropFilter: "blur(12px)",
          borderBottom: "1px solid rgba(194,201,187,0.3)",
          flexShrink: 0,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
          <button className="btn-icon" onClick={() => navigate(backTo)} title="Back to library">
            <span className="icon" style={{ fontSize: 22 }}>arrow_back</span>
          </button>
        </div>

        <h1 style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 17, fontWeight: 400, margin: 0, maxWidth: "40%", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
          {book.title}
        </h1>

        <div style={{ display: "flex", alignItems: "center", gap: 2 }}>
          <button
            className="btn-icon"
            title={activeBookmark ? "Remove bookmark" : "Bookmark this page"}
            onClick={toggleBookmark}
            style={activeBookmark ? { color: "var(--primary)", background: "var(--surface-container-high)" } : {}}
          >
            <span
              className="icon"
              style={{ fontSize: 22, fontVariationSettings: activeBookmark ? "'FILL' 1" : undefined }}
            >
              bookmark
            </span>
          </button>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              background: "rgba(128,128,128,0.14)",
              borderRadius: 8,
              padding: 2,
              margin: "0 4px",
            }}
          >
            <button
              className="btn-icon"
              title="Scroll reading mode"
              onClick={() => switchMode("scroll")}
              style={{
                width: 32,
                height: 32,
                color: theme.mode === "scroll" ? "var(--primary)" : undefined,
                background: theme.mode === "scroll" ? "var(--surface-container-high)" : undefined,
              }}
            >
              <span className="icon" style={{ fontSize: 20 }}>swap_vert</span>
            </button>
            <button
              className="btn-icon"
              title="Paginate reading mode"
              onClick={() => switchMode("paginate")}
              style={{
                width: 32,
                height: 32,
                color: theme.mode === "paginate" ? "var(--primary)" : undefined,
                background: theme.mode === "paginate" ? "var(--surface-container-high)" : undefined,
              }}
            >
              <span className="icon" style={{ fontSize: 20 }}>menu_book</span>
            </button>
          </div>
          <button
            className="btn-icon"
            title="Highlights & notes"
            onClick={() => setPanel((p) => (p === "highlights" ? null : "highlights"))}
            style={panel === "highlights" ? { color: "var(--primary)", background: "var(--surface-container-high)" } : {}}
          >
            <span className="icon" style={{ fontSize: 22 }}>edit_note</span>
          </button>
          <button
            className="btn-icon"
            title="Reading settings"
            onClick={() => setPanel((p) => (p === "settings" ? null : "settings"))}
            style={panel === "settings" ? { color: "var(--primary)", background: "var(--surface-container-high)" } : {}}
          >
            <span className="icon" style={{ fontSize: 22 }}>format_size</span>
          </button>
        </div>
      </header>

      {/* Body */}
      <div style={{ display: "flex", flex: 1, minHeight: 0, position: "relative" }}>
        <div
          ref={scrollRef}
          style={{
            flex: 1,
            overflowY: "auto",
            padding: theme.mode === "paginate" ? "24px" : `48px ${theme.margins}px 120px`,
            display: theme.mode === "paginate" ? "flex" : "block",
          }}
        >
          {reflowAvailable ? (
            theme.mode === "paginate" ? (
              <BookPaginate
                key={book.id}
                contentKey={book.id}
                blocks={allBlocks}
                theme={theme}
                initialProgress={progressLoaded ? progress : 0}
                onPageChange={handleBookPageChange}
                spread={theme.pageLayout === "spread"}
              />
            ) : (
              <ReflowView data={structuredText} theme={theme} currentPage={currentPage} setCurrentPage={setCurrentPage} pageRefs={pageRefs} />
            )
          ) : (
            <div style={{ maxWidth: 720, margin: "0 auto" }}>
              <p className="text-muted" style={{ marginBottom: 16 }}>
                Reflow mode isn't available for this book (likely scanned or complex layout).
              </p>
              <iframe
                title="pdf"
                src={book.pdf_url}
                style={{ width: "100%", height: "76vh", border: "1px solid var(--outline-variant)", borderRadius: 8 }}
              />
            </div>
          )}
        </div>

        {panel && (
          <div
            style={{
              position: "absolute",
              top: 0,
              right: 0,
              bottom: 0,
              display: "flex",
              zIndex: 30,
            }}
          >
            {panel === "highlights" && (
              <HighlightsPanel
                annotations={annotations}
                bookId={bookId}
                setAnnotations={setAnnotations}
                theme={theme}
                onClose={() => setPanel(null)}
              />
            )}

            {panel === "settings" && (
              <ThemeControls
                theme={theme}
                setTheme={setTheme}
                reflowAvailable={reflowAvailable}
                onClose={() => setPanel(null)}
              />
            )}
          </div>
        )}
      </div>

      {/* Bottom toolbar */}
      <footer
        style={{
          height: 56,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 24,
          padding: "0 24px",
          background: theme.themeId === "dark" || theme.themeId === "night" ? "rgba(27,27,31,0.95)" : "rgba(252,249,248,0.95)",
          backdropFilter: "blur(12px)",
          borderTop: "1px solid rgba(194,201,187,0.3)",
          flexShrink: 0,
          zIndex: 20,
        }}
      >
        <div style={{ fontSize: 12, color: "var(--on-surface-variant)", whiteSpace: "nowrap", display: "flex", alignItems: "center", gap: 10 }}>
          {theme.mode === "scroll" && pageCount > 0 && (
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <span>Page</span>
              <input
                type="number"
                min={1}
                max={pageCount || 1}
                value={jumpValue}
                onFocus={() => setJumpFocused(true)}
                onBlur={() => {
                  setJumpFocused(false);
                  jumpToPage(jumpValue);
                }}
                onChange={(e) => setJumpValue(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    jumpToPage(jumpValue);
                    e.currentTarget.blur();
                  }
                }}
                style={{
                  width: 56,
                  padding: "4px 6px",
                  textAlign: "center",
                  fontSize: 12,
                  fontFamily: "inherit",
                  color: "var(--on-surface)",
                  background: "var(--surface-container-lowest)",
                  border: "1px solid var(--outline-variant)",
                  borderRadius: 6,
                  outline: "none",
                }}
              />
              <span>of {pageCount || "—"}</span>
            </div>
          )}
          <span>{Math.round(progress)}% read</span>
        </div>
        <div style={{ flex: 1, maxWidth: 640, display: "flex", alignItems: "center", gap: 16 }}>
          <span style={{ fontSize: 11, color: "var(--on-surface-variant)" }}>0%</span>
          <div style={{ flex: 1 }}>
            <div className="progress-track" style={{ height: 4, background: "var(--outline-variant)" }}>
              <div className="progress-fill" style={{ width: `${progress}%` }} />
            </div>
          </div>
          <span style={{ fontSize: 11, color: "var(--on-surface-variant)" }}>100%</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontSize: 12, color: "var(--on-surface-variant)" }}>Reflow</span>
          <button
            role="switch"
            aria-checked={reflowAvailable}
            onClick={() => {}}
            style={{
              width: 36,
              height: 20,
              borderRadius: 999,
              background: reflowAvailable ? "var(--primary)" : "var(--outline-variant)",
              border: "none",
              position: "relative",
              transition: "background-color 0.2s",
            }}
          >
            <span
              style={{
                position: "absolute",
                top: 2,
                left: reflowAvailable ? 18 : 2,
                width: 16,
                height: 16,
                borderRadius: "50%",
                background: "#fff",
                boxShadow: "0 1px 3px rgba(0,0,0,0.3)",
                transition: "left 0.2s",
              }}
            />
          </button>
        </div>
      </footer>
    </div>
  );
}

function ReflowView({ data, theme, currentPage, setCurrentPage, pageRefs }) {
  const pages = data.pages || [];
  return (
    <div
      style={{
        maxWidth: 720,
        margin: "0 auto",
        background: theme.themeId === "sepia" ? "#fdfbf6" : theme.themeId === "dark" ? "#262626" : theme.themeId === "night" ? "#1e293b" : "var(--surface-container-lowest)",
        border: "1px solid var(--outline-variant)",
        borderRadius: 12,
        boxShadow: "0 4px 30px rgba(63,56,39,0.05)",
        padding: "56px 64px",
        fontFamily: theme.font,
        fontSize: theme.fontSize,
        lineHeight: theme.lineSpacing,
        color: theme.textColor,
      }}
    >
      {pages.flatMap((page, pageIdx) => {
        const blocks = (page.blocks || []).filter((b) => b.text && b.text.trim());
        const onScreen = (el) => {
          if (!el) return;
          const rect = el.getBoundingClientRect();
          if (rect.top < 100) {
            setCurrentPage(pageIdx + 1);
          }
        };
        return [
          <div
            key={`page-${page.page_number || pageIdx}`}
            ref={(el) => {
              pageRefs.current[pageIdx] = el;
              onScreen(el);
            }}
          >
            {blocks.map((block, i) =>
              block.kind === "heading" ? (
                <h2
                  key={i}
                  style={{
                    fontFamily: "var(--font-display)",
                    fontSize: theme.fontSize * 1.45,
                    fontWeight: 700,
                    margin: "1.6em 0 0.7em",
                    lineHeight: 1.3,
                    color: theme.textColor,
                  }}
                >
                  {block.text}
                </h2>
              ) : (
                <p key={i} style={{ margin: "0 0 1.1em" }}>
                  {block.text}
                </p>
              )
            )}
          </div>,
          pageIdx < pages.length - 1 ? (
            <div
              key={`pb-${page.page_number || pageIdx}`}
              style={{ borderTop: "1px solid rgba(128,128,128,0.25)", margin: "2.5em auto", width: "40%", textAlign: "center" }}
            />
          ) : null,
        ];
      })}
    </div>
  );
}


function HighlightsPanel({ annotations, bookId, setAnnotations, theme, onClose }) {
  const [composing, setComposing] = useState(false);
  const [kind, setKind] = useState("highlight");
  const [anchor, setAnchor] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const composeRef = useRef(null);

  const refreshList = async () => {
    try {
      setAnnotations(await api(`/sync/annotations/${bookId}`));
    } catch {}
  };

  const removeAnnotation = async (id) => {
    try {
      await api(`/sync/annotations/${id}`, { method: "DELETE" });
      setAnnotations((prev) => prev.filter((a) => a.id !== id));
    } catch {}
  };

  const startCompose = () => {
    setKind("highlight");
    setAnchor("");
    setNote("");
    setComposing(true);
    setTimeout(() => composeRef.current?.scrollIntoView({ behavior: "smooth", block: "nearest" }), 0);
  };

  const saveAnnotation = async () => {
    const text = note.trim();
    if (!text && !anchor.trim()) return;
    setSaving(true);
    try {
      await api("/sync/annotations", {
        method: "POST",
        body: {
          book_id: bookId,
          kind: text && !anchor.trim() ? "note" : kind,
          anchor: anchor.trim(),
          note_text: text || null,
        },
      });
      setComposing(false);
      await refreshList();
    } catch {}
    setSaving(false);
  };

  return (
    <aside
      style={{
        width: 340,
        borderLeft: "1px solid rgba(194,201,187,0.3)",
        background: "var(--surface-container-low)",
        color: "var(--on-surface)",
        display: "flex",
        flexDirection: "column",
        flexShrink: 0,
        boxShadow: "-16px 0 40px rgba(0,0,0,0.18)",
      }}
    >
      <div style={{ padding: "16px 20px", borderBottom: "1px solid rgba(194,201,187,0.3)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h3 style={{ fontFamily: "var(--font-display)", fontSize: 16, margin: 0 }}>Highlights & Notes</h3>
        <button className="btn-icon" onClick={onClose} title="Close">
          <span className="icon" style={{ fontSize: 16 }}>close</span>
        </button>
      </div>
      <div style={{ flex: 1, overflowY: "auto", padding: 20 }}>
        {annotations.length === 0 ? (
          <div className="text-muted" style={{ fontSize: 14 }}>
            No bookmarks or notes yet. Bookmark a page from the reader to save your place.
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
            {annotations.map((a) => (
              <div key={a.id} style={{ display: "flex", gap: 8, alignItems: "flex-start" }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div
                    style={{
                      borderLeft: "3px solid var(--primary)",
                      paddingLeft: 10,
                      fontSize: 14,
                      color: "var(--on-surface-variant)",
                      display: "flex",
                      alignItems: "center",
                      gap: 6,
                    }}
                  >
                    {a.kind === "bookmark" && (
                      <span className="icon" style={{ fontSize: 15, color: "var(--primary)" }}>bookmark</span>
                    )}
                    <span style={{ fontStyle: a.kind !== "bookmark" ? "italic" : "normal" }}>
                      {a.kind === "bookmark"
                        ? a.anchor
                        : a.kind === "note" && !a.anchor
                        ? "Note"
                        : a.kind === "note"
                        ? a.anchor
                        : `"${a.anchor}"`}
                    </span>
                  </div>
                  {a.note_text && (
                    <div
                      className="card"
                      style={{
                        padding: 10,
                        fontSize: 13,
                        marginTop: 8,
                        background: "var(--surface-container-lowest)",
                        color: "var(--on-surface)",
                        whiteSpace: "pre-wrap",
                      }}
                    >
                      {a.note_text}
                    </div>
                  )}
                </div>
                <button className="btn-icon" title="Delete" onClick={() => removeAnnotation(a.id)} style={{ flexShrink: 0 }}>
                  <span className="icon" style={{ fontSize: 16 }}>close</span>
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
      <div ref={composeRef} style={{ padding: 16, borderTop: "1px solid rgba(194,201,187,0.3)" }}>
        {composing ? (
          <div
            className="card"
            style={{ padding: 14, display: "flex", flexDirection: "column", gap: 12 }}
          >
            <div
              style={{
                display: "flex",
                background: "var(--surface-container-low)",
                borderRadius: 8,
                padding: 4,
                border: "1px solid var(--outline-variant)",
              }}
            >
              {[
                { id: "highlight", label: "Highlight", icon: "format_quote" },
                { id: "note", label: "Note", icon: "edit_note" },
              ].map((k) => (
                <button
                  key={k.id}
                  onClick={() => setKind(k.id)}
                  style={{
                    flex: 1,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: 6,
                    padding: "7px 12px",
                    borderRadius: 6,
                    border: "none",
                    background: kind === k.id ? "var(--surface-container-high)" : "transparent",
                    color: kind === k.id ? "var(--on-surface)" : "var(--on-surface-variant)",
                    fontWeight: 500,
                    fontSize: 13,
                    fontFamily: "inherit",
                    cursor: "pointer",
                  }}
                >
                  <span className="icon" style={{ fontSize: 16 }}>{k.icon}</span>
                  {k.label}
                </button>
              ))}
            </div>
            {kind === "highlight" && (
              <input
                placeholder="Passage text (optional)"
                value={anchor}
                onChange={(e) => setAnchor(e.target.value)}
                style={{
                  fontSize: 14,
                  fontFamily: "var(--font-body)",
                  padding: "10px 12px",
                  borderRadius: 8,
                  border: "1px solid var(--outline-variant)",
                  background: "var(--surface-container-low)",
                  color: "var(--on-surface)",
                  outline: "none",
                }}
              />
            )}
            <textarea
              placeholder={kind === "highlight" ? "Write a note…" : "Write your note…"}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={3}
              style={{
                fontSize: 14,
                fontFamily: "var(--font-body)",
                padding: "10px 12px",
                borderRadius: 8,
                border: "1px solid var(--outline-variant)",
                background: "var(--surface-container-low)",
                color: "var(--on-surface)",
                outline: "none",
                resize: "vertical",
              }}
            />
            <div style={{ display: "flex", gap: 8 }}>
              <button
                className="btn btn-ghost"
                onClick={() => setComposing(false)}
                style={{ flex: 1, fontSize: 13, padding: "10px 16px" }}
                disabled={saving}
              >
                Cancel
              </button>
              <button
                className="btn btn-primary"
                onClick={saveAnnotation}
                style={{ flex: 1, fontSize: 13, padding: "10px 16px" }}
                disabled={saving || (!note.trim() && !anchor.trim())}
              >
                {saving ? "Saving…" : "Save"}
              </button>
            </div>
          </div>
        ) : (
          <button className="btn btn-ghost btn-block" onClick={startCompose} style={{ fontSize: 13 }}>
            <span className="icon" style={{ fontSize: 16 }}>add</span>
            New annotation
          </button>
        )}
      </div>
    </aside>
  );
}
