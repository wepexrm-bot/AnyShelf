import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams, useNavigate, useLocation } from "react-router-dom";
import ThemeControls, { FONT_OPTIONS, THEME_PRESETS } from "./ThemeControls";
import { TextLayerScrollView, TextLayerPaginateView, resolveHighlights } from "./TextLayerView";
import { loadPdf } from "../pdfjs";
import { api } from "../api";

// Page boxes for books without a textlayer-v1 extraction: derive them from the
// PDF itself so the book still renders as real pages (no selectable overlay
// until the book is re-extracted).
async function pdfPagesFromDoc(pdfDoc) {
  const pages = [];
  for (let i = 1; i <= pdfDoc.numPages; i++) {
    const p = await pdfDoc.getPage(i);
    const vp = p.getViewport({ scale: 1 });
    pages.push({ page: i, width: vp.width, height: vp.height, rotation: vp.rotation, runs: [] });
  }
  return pages;
}

// Zoom is client-side only (per browser) so it never collides with the shared
// server `font_size` field that mobile uses for its own zoom control.
function storedZoom() {
  try {
    const raw = JSON.parse(localStorage.getItem("reader_zoom"));
    if (raw === "width" || raw === "page") return raw;
    if (typeof raw === "number" && raw >= 10 && raw <= 400) return raw;
  } catch {}
  return "width";
}

function storedTextMode() {
  try {
    const raw = JSON.parse(localStorage.getItem("reader_textmode"));
    if (typeof raw === "boolean") return raw;
  } catch {}
  return true;
}

const DEFAULT_THEME = {
  themeId: "light",
  background: "#fcf9f8",
  surface: "#ffffff",
  textColor: "#1b1c1c",
  fontId: "serif",
  font: FONT_OPTIONS[0].stack,
  fontSize: 20,
  lineSpacing: 1.6,
  marginId: "medium",
  margins: 96,
  mode: "scroll",
  pageLayout: "single",
  zoom: storedZoom(),
  textMode: storedTextMode(),
};

function hexToRgba(hex, alpha) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || "");
  if (!m) return `rgba(128,128,128,${alpha})`;
  const n = parseInt(m[1], 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}

// The reader paints its own background/text from `theme`, so the app-wide
// CSS tokens (--surface-container-lowest, --on-surface, ...) must be
// overridden scoped to the reader to match the reader's theme. Without this,
// a light reader theme inside a dark-mode app would render dark surfaces
// with dark text (invisible content).
function readerThemeVars(theme) {
  const dark = theme.themeId === "dark" || theme.themeId === "night";
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
  const [pdfDoc, setPdfDoc] = useState(null);
  const [layoutPages, setLayoutPages] = useState(null);
  const [extraction, setExtraction] = useState(null);
  const [theme, setTheme] = useState(DEFAULT_THEME);
  const [panel, setPanel] = useState(null);
  const [annotations, setAnnotations] = useState([]);
  const [progress, setProgress] = useState(0);
  const [progressLoaded, setProgressLoaded] = useState(false);
  const [currentPage, setCurrentPage] = useState(0);
  const [pageCount, setPageCount] = useState(0);
  const scrollRef = useRef(null);
  const pageRefs = useRef([]);
  const settingsHydratedRef = useRef(false);
  const [jumpValue, setJumpValue] = useState("1");
  const [jumpFocused, setJumpFocused] = useState(false);
  const [chromeVisible, setChromeVisible] = useState(true);

  const highlights = useMemo(
    () => (layoutPages?.length ? resolveHighlights(annotations, layoutPages) : new Map()),
    [annotations, layoutPages]
  );

  const handlePageNav = useCallback((idx, total) => {
    setCurrentPage(idx + 1);
    if (total > 0) setProgress(((idx + 1) / total) * 100);
  }, []);

  const jumpToPage = useCallback(
    (raw) => {
      const n = parseInt(raw, 10);
      if (!n || !pageCount) return;
      const clamped = Math.max(1, Math.min(pageCount, n));
      setJumpValue(String(clamped));
      if (theme.mode === "paginate") {
        handlePageNav(clamped - 1, pageCount);
        return;
      }
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
    [pageCount, theme.mode, handlePageNav]
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

  // Clicking the reading surface toggles the chrome (header/footer/settings).
  // Ignore clicks on interactive elements and text selections so toggling never
  // fights the user's page-turns or highlighting.
  const toggleChrome = useCallback((e) => {
    if (e.target.closest("button, input, a, iframe")) return;
    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && sel.toString().length > 0) return;
    setChromeVisible((v) => {
      if (v) setPanel(null);
      return !v;
    });
  }, []);

  // Text selection in the page -> create a char-range highlight.
  const createHighlight = useCallback(
    async (page, startChar, endChar, text) => {
      if (!text) return;
      try {
        await api("/sync/annotations", {
          method: "POST",
          body: {
            book_id: bookId,
            kind: "highlight",
            anchor: JSON.stringify({ page, start_char: startChar, end_char: endChar, text }),
            note_text: null,
          },
        });
        await refreshAnnotations();
      } catch (err) {
        alert(err.message);
      }
    },
    [bookId, refreshAnnotations]
  );

  // Persist reading-mode changes made from the header toggle. Guarded by a
  // hydration ref so the effect never fires while the saved settings are still
  // loading (otherwise the still-default theme would overwrite the server row).
  useEffect(() => {
    if (!book || !settingsHydratedRef.current) return;
    const timer = setTimeout(() => {
      api("/settings/", {
        method: "PUT",
        body: {
          theme: theme.themeId,
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
    let cancelled = false;
    let timer = null;

    const loadBook = async () => {
      setBook(null);
      setStructuredText(null);
      setPdfDoc(null);
      setLayoutPages(null);
      setPageCount(0);
      setProgress(0);
      setProgressLoaded(false);
      setCurrentPage(0);
      setAnnotations([]);
      settingsHydratedRef.current = false;
      const data = await api(`/books/${bookId}`);
      if (cancelled) return;
      setBook(data);
      let totalPages = 0;
      const extractingNow =
        data.extraction_status === "pending" || data.extraction_status === "processing";
      setExtraction(
        extractingNow ? { status: data.extraction_status, progress: 0 } : null
      );
      if (extractingNow && !timer) timer = setTimeout(poll, 1000);

      let st = null;
      if (data.structured_text_url) {
        for (let attempt = 0; attempt < 3 && !st; attempt++) {
          try {
            const res = await fetch(data.structured_text_url);
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            st = await res.json();
          } catch {
            if (cancelled) return;
            if (attempt < 2) await new Promise((r) => setTimeout(r, 600 * (attempt + 1)));
          }
        }
        if (cancelled) return;
        setStructuredText(st);
      }

      // Render the real PDF with pdf.js (images/vectors/fonts faithful). A
      // textlayer-v1 extraction supplies the selectable runs + page boxes;
      // otherwise the page boxes are synthesized from the PDF so the book
      // still renders (with no text overlay until it is re-extracted).
      let layoutPages = null;
      let loadedPdf = null;
      if (data.pdf_url && !cancelled) {
        try {
          loadedPdf = await loadPdf(data.pdf_url);
          if (cancelled) return;
          setPdfDoc(loadedPdf);
        } catch {
          // PDF render is best-effort; the text layer still works standalone.
        }
      }
      if (st?.schema === "textlayer-v1" && st?.pages?.length) {
        layoutPages = st.pages;
      } else if (loadedPdf) {
        layoutPages = await pdfPagesFromDoc(loadedPdf);
        if (cancelled) return;
      }
      if (cancelled) return;
      setLayoutPages(layoutPages);
      totalPages = layoutPages?.length || 0;
      setPageCount(totalPages);

      const [savedSettings, savedProgress, savedAnnotations] = await Promise.all([
        api("/settings/").catch(() => null),
        api(`/sync/progress/${bookId}`).catch(() => null),
        api(`/sync/annotations/${bookId}`).catch(() => []),
      ]);
      if (cancelled) return;

      if (savedSettings) {
        const preset = THEME_PRESETS.find((p) => p.id === savedSettings.theme) || THEME_PRESETS[0];
        const font = FONT_OPTIONS.find((f) => f.id === savedSettings.font_family) || FONT_OPTIONS[0];
        setTheme((prev) => ({
          ...prev,
          themeId: savedSettings.theme,
          background: preset.background,
          surface: preset.surface,
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
          pageLayout: savedSettings.page_layout || "single",
        }));
      }
      settingsHydratedRef.current = true;

      if (savedProgress) {
        const pc = savedProgress.current_page || 0;
        setProgress(pc);
        // Paginate mode has no scroll position to restore, so resume at the
        // page that matches the saved percentage. Scroll mode restores via
        // scrollTop in its own effect.
        const mode = (savedSettings && savedSettings.reading_mode) || "scroll";
        const total = totalPages || 0;
        if (mode === "paginate" && total > 0 && pc > 0) {
          const pageNum = Math.max(1, Math.min(total, Math.round((pc / 100) * total)));
          setCurrentPage(pageNum);
        }
      }
      setProgressLoaded(true);
      setAnnotations(savedAnnotations);
    };

    const poll = async () => {
      if (cancelled) return;
      timer = null;
      try {
        const r = await api(`/books/${bookId}/progress`);
        if (cancelled) return;
        if (r.extraction_status === "pending" || r.extraction_status === "processing") {
          setExtraction({ status: r.extraction_status, progress: r.progress });
          timer = setTimeout(poll, 1000);
        } else {
          setExtraction(null);
          await loadBook();
        }
      } catch {
        if (!cancelled) timer = setTimeout(poll, 1000);
      }
    };

    loadBook();

    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [bookId]);

  // Track scroll depth -> reading progress + current page (scroll mode)
  useEffect(() => {
    if (theme.mode !== "scroll") return;
    const el = scrollRef.current;
    if (!el) return;
    let raf = null;
    const updateFromScroll = () => {
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = null;
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
      });
    };
    el.addEventListener("scroll", updateFromScroll);
    updateFromScroll();
    return () => {
      el.removeEventListener("scroll", updateFromScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, [book, theme.mode]);

  // Resume at the current relative position whenever entering scroll mode,
  // but only after saved progress has actually loaded (otherwise it would
  // restore to 0% / page 1 before the server responds). Re-applies once
  // web fonts finish loading so a late reflow doesn't throw off the spot.
  const lastRestoreTopRef = useRef(-1);
  useEffect(() => {
    if (theme.mode !== "scroll" || !book || !layoutPages?.length || !progressLoaded) return;
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
  }, [theme.mode, book, layoutPages, progressLoaded]);

  // Sync progress + record session when scrolling settles
  useEffect(() => {
    if (!bookId || progress === 0) return;
    const timer = setTimeout(() => {
      api("/sync/progress", {
        method: "POST",
        body: { book_id: bookId, current_page: progress, current_offset: progress / 100 },
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

  if (!book) return <div className="loading">Loading book…</div>;

  if (extraction) {
    const pct = Math.min(100, Math.max(0, Math.round(extraction.progress || 0)));
    return (
      <div
        style={{
          height: "100vh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "24px",
          background: theme.background,
          color: theme.textColor,
        }}
      >
        <div
          style={{
            width: 56,
            height: 56,
            borderRadius: "50%",
            border: "4px solid rgba(128,128,128,0.25)",
            borderTopColor: "var(--primary, #1a73e8)",
            animation: "readerSpin 1s linear infinite",
          }}
        />
        <div style={{ textAlign: "center" }}>
          <div style={{ fontWeight: 600, marginBottom: 4 }}>
            {extraction.status === "pending" ? "Preparing your book…" : "Processing pages…"}
          </div>
          <div style={{ opacity: 0.7, fontSize: 14 }}>
            {extraction.status === "pending"
              ? "Your book is in the queue"
              : `Extracting text and layout${pct > 0 ? ` — ${pct}%` : ""}`}
          </div>
        </div>
      </div>
    );
  }

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
          height: chromeVisible ? 56 : 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 24px",
          background: hexToRgba(theme.background, 0.9),
          backdropFilter: "blur(12px)",
          borderBottom: chromeVisible ? "1px solid rgba(194,201,187,0.3)" : "none",
          flexShrink: 0,
          zIndex: 20,
          overflow: "hidden",
          opacity: chromeVisible ? 1 : 0,
          transition: "height 0.22s ease, opacity 0.18s ease",
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
          {structuredText?.outline?.length > 0 && (
            <button
              className="btn-icon"
              title="Table of contents"
              onClick={() => setPanel((p) => (p === "toc" ? null : "toc"))}
              style={panel === "toc" ? { color: "var(--primary)", background: "var(--surface-container-high)" } : {}}
            >
              <span className="icon" style={{ fontSize: 22 }}>toc</span>
            </button>
          )}
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
            title={theme.textMode ? "Text mode: on (click to show original PDF)" : "Text mode: off (click to use your font)"}
            onClick={() => {
              setTheme((t) => ({ ...t, textMode: !t.textMode }));
              try {
                localStorage.setItem("reader_textmode", JSON.stringify(!theme.textMode));
              } catch {}
            }}
            style={
              theme.textMode
                ? { color: "var(--primary)", background: "var(--surface-container-high)" }
                : undefined
            }
          >
            <span className="icon" style={{ fontSize: 20 }}>text_fields</span>
          </button>
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
      <div style={{ display: "flex", flex: 1, minHeight: 0, position: "relative" }} onClick={toggleChrome}>
        <div
          ref={scrollRef}
          style={{
            flex: 1,
            minHeight: 0,
            position: "relative",
            overflowY: theme.mode === "paginate" ? "hidden" : "auto",
            overflowX: theme.mode === "paginate" ? "hidden" : "auto",
          }}
        >
          {layoutPages?.length ? (
            theme.mode === "paginate" ? (
              <TextLayerPaginateView
                key={book.id}
                pages={layoutPages}
                theme={theme}
                pageLayout={theme.pageLayout}
                highlights={highlights}
                pdfDoc={pdfDoc}
                page={Math.min(Math.max(currentPage - 1, 0), pageCount - 1)}
                onPageChange={handlePageNav}
                onSelectionCapture={createHighlight}
              />
            ) : (
              <TextLayerScrollView
                key={book.id}
                pages={layoutPages}
                theme={theme}
                highlights={highlights}
                pdfDoc={pdfDoc}
                pageRefs={pageRefs}
                onSelectionCapture={createHighlight}
              />
            )
          ) : (
            <div style={{ maxWidth: 720, margin: "0 auto", padding: "48px 24px 120px" }}>
              <p className="text-muted">
                No readable pages are available for this book yet.
              </p>
            </div>
          )}
        </div>

        {panel && (
          <div
            onClick={(e) => e.stopPropagation()}
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

            {panel === "toc" && (
              <TocPanel
                outline={structuredText?.outline || []}
                currentPage={currentPage}
                onSelect={(page) => {
                  setPanel(null);
                  jumpToPage(String(page + 1));
                }}
                onClose={() => setPanel(null)}
              />
            )}

            {panel === "settings" && (
              <ThemeControls
                theme={theme}
                setTheme={setTheme}
                onClose={() => setPanel(null)}
              />
            )}
          </div>
        )}
      </div>

      {/* Bottom toolbar */}
      <footer
        style={{
          height: chromeVisible ? 56 : 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 24,
          padding: "0 24px",
          background: hexToRgba(theme.background, 0.95),
          backdropFilter: "blur(12px)",
          borderTop: chromeVisible ? "1px solid rgba(194,201,187,0.3)" : "none",
          flexShrink: 0,
          zIndex: 20,
          overflow: "hidden",
          opacity: chromeVisible ? 1 : 0,
          transition: "height 0.22s ease, opacity 0.18s ease",
        }}
      >
        <div style={{ fontSize: 12, color: "var(--on-surface-variant)", whiteSpace: "nowrap", display: "flex", alignItems: "center", gap: 10 }}>
          {pageCount > 0 && (
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
        <div style={{ fontSize: 12, color: "var(--on-surface-variant)" }}>
          {Math.round(currentPage || 0)} / {pageCount || "—"}
        </div>
      </footer>
    </div>
  );
}

function TocPanel({ outline, currentPage, onSelect, onClose }) {
  return (
    <aside
      style={{
        width: 320,
        borderLeft: "1px solid rgba(194,201,187,0.3)",
        borderTopLeftRadius: 16,
        borderBottomLeftRadius: 16,
        overflow: "hidden",
        background: "var(--surface-container-low)",
        color: "var(--on-surface)",
        display: "flex",
        flexDirection: "column",
        flexShrink: 0,
        boxShadow: "-16px 0 40px rgba(0,0,0,0.18)",
      }}
    >
      <div style={{ padding: "16px 20px", borderBottom: "1px solid rgba(194,201,187,0.3)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h3 style={{ fontFamily: "var(--font-display)", fontSize: 16, margin: 0 }}>Table of Contents</h3>
        <button className="btn-icon" onClick={onClose} title="Close">
          <span className="icon" style={{ fontSize: 16 }}>close</span>
        </button>
      </div>
      <div style={{ flex: 1, overflowY: "auto", padding: "12px 0" }}>
        {outline.length === 0 ? (
          <div className="text-muted" style={{ fontSize: 14, padding: "0 20px" }}>
            No table of contents found.
          </div>
        ) : (
          outline.map((item, i) => {
            const pad = Math.min(item.level, 6) * 14;
            const active = currentPage === item.page + 1;
            return (
              <button
                key={i}
                onClick={() => onSelect(item.page)}
                style={{
                  width: "100%",
                  display: "flex",
                  alignItems: "baseline",
                  gap: 8,
                  padding: "8px 20px",
                  paddingLeft: 20 + pad,
                  border: "none",
                  background: active ? "rgba(21,66,18,0.08)" : "transparent",
                  color: active ? "var(--primary)" : "var(--on-surface)",
                  textAlign: "left",
                  cursor: "pointer",
                  fontSize: item.level > 1 ? 13 : 14,
                  fontWeight: item.level === 1 ? 600 : 400,
                  fontFamily: "inherit",
                }}
              >
                <span style={{ flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {item.title}
                </span>
                <span style={{ fontSize: 11, color: "var(--on-surface-variant)", flexShrink: 0 }}>
                  {item.page + 1}
                </span>
              </button>
            );
          })
        )}
      </div>
    </aside>
  );
}

function anchorLabel(a) {  if (a.kind === "bookmark") return a.anchor;
  if (a.anchor && a.anchor.startsWith("{")) {
    try {
      const p = JSON.parse(a.anchor);
      if (p.text) return `"${p.text}"`;
      if (typeof p.page === "number") return `Page ${p.page + 1}`;
    } catch {}
  }
  return a.anchor || "Note";
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
        borderTopLeftRadius: 16,
        borderBottomLeftRadius: 16,
        overflow: "hidden",
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
            No highlights, notes, or bookmarks yet. Select text in the reader to highlight, or
            bookmark a page from the header.
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
                    <span style={{ fontStyle: a.kind !== "bookmark" ? "italic" : "normal", overflowWrap: "anywhere" }}>
                      {anchorLabel(a)}
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
