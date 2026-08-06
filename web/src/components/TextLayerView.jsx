import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

// Rendering for the backend text-layer JSON (schema `textlayer-v1`): each PDF
// page is a positioned set of text runs (x/baseline/font-size/advance), rendered
// in the reader font with per-line scaleX fitting -- the same technique as the
// extraction-lab reader, so the PDF's native layout is preserved faithfully.

const PAGE_INSETS = { small: 48, medium: 96, large: 144 };
const SCROLL_MAX_WIDTH = 860;

export function insetPx(theme) {
  // Margins come from the actual theme value (48/96/144) set by the settings
  // panel; the id map above is only a fallback for stale themes.
  return theme.margins ?? PAGE_INSETS[theme.marginId] ?? PAGE_INSETS.medium;
}

// The anchor a reader creates stores {page,start_char,end_char,text} (JSON) or a
// plain quoted text. Imported PDF annotations store the JSON form. Returns
// Map(page -> [{start,end,color}]).
export function resolveHighlights(annotations, pages) {
  const pageTexts = pages.map((p) => (p.runs || []).map((r) => r.t).join(""));
  const byPage = new Map();
  const add = (page, start, end, color) => {
    if (!byPage.has(page)) byPage.set(page, []);
    byPage.get(page).push({ start, end, color: color || "#FFD54F" });
  };
  for (const a of annotations || []) {
    if (a.kind !== "highlight") continue;
    let page, start, end, text;
    let parsed = null;
    try {
      parsed = a.anchor && a.anchor.startsWith("{") ? JSON.parse(a.anchor) : null;
    } catch {}
    if (parsed) {
      page = parsed.page;
      start = parsed.start_char;
      end = parsed.end_char;
      text = parsed.text;
    } else {
      text = (a.anchor || "").trim();
      if (!text) continue;
    }
    if (typeof page === "number" && Number.isInteger(start) && Number.isInteger(end)) {
      add(page, start, end, a.color);
      continue;
    }
    // Fallback: locate the quoted text in the page stream.
    if (text) {
      for (let i = 0; i < pages.length; i++) {
        const idx = pageTexts[i].indexOf(text);
        if (idx >= 0) {
          add(i, idx, idx + text.length, a.color);
          break;
        }
      }
    }
  }
  return byPage;
}

// Per-page fit measurements, cached by (page signature, font, width, zoom).
// Values are only stored AFTER the reader font has finished loading, so a hit
// never re-applies fallback-font scaleX (which previously made words collapse).
const fitCache = new Map();

// Port of the lab reader's applyTextScaling: compute each span's scaleX so the
// reader font stretches to the PDF's intended advance width. Measurement uses
// an offscreen canvas (pure math, no DOM reads) so fitting many spans never
// triggers a forced reflow.
function measureFit(root, fontFamily, pageW) {
  const spans = [...root.querySelectorAll("span.tl")];
  const idxBySpan = new Map(spans.map((s, i) => [s, i]));
  const sx = new Array(spans.length).fill(undefined);
  const ctx = document.createElement("canvas").getContext("2d");
  const lines = new Map();
  for (const s of spans) {
    const top = Math.round(parseFloat(s.style.top));
    if (!lines.has(top)) lines.set(top, []);
    lines.get(top).push(s);
  }
  for (const arr of lines.values()) {
    arr.sort((a, b) => parseFloat(a.style.left) - parseFloat(b.style.left));
    for (let i = 0; i < arr.length; i++) {
      const s = arr[i];
      const fs = parseFloat(s.style.fontSize);
      const ow = parseFloat(s.dataset.ow);
      const left = parseFloat(s.style.left);
      if (!(ow > 0) || !s.textContent.length || !(fs > 0)) continue;
      const nextLeft = i + 1 < arr.length ? parseFloat(arr[i + 1].style.left) : Infinity;
      const target = Math.min(ow, nextLeft - left, pageW - left) * 0.995;
      if (!(target > 0)) continue;
      ctx.font = `${fs}px ${fontFamily}`;
      const natural = ctx.measureText(s.textContent).width;
      if (natural > 0) {
        const k = idxBySpan.get(s);
        if (k != null) sx[k] = target / natural;
      }
    }
  }
  return sx;
}

function applyFitCache(root, sx) {
  let i = 0;
  for (const s of root.querySelectorAll("span.tl")) {
    const v = sx[i++];
    if (v != null) s.style.setProperty("--sx", String(v));
  }
}

async function ensureFontReady(fontFamily) {
  try {
    if (document.fonts && typeof document.fonts.load === "function") {
      await document.fonts.load(`20px ${fontFamily}`);
    }
  } catch {}
}

function pageSignature(page, pageIdx) {
  const r = page.runs || [];
  return `${pageIdx}:${page.width}:${page.height}:${r.length}:${r[0]?.t ?? ""}:${r[r.length - 1]?.t ?? ""}`;
}

const PageSurface = React.memo(function PageSurface({
  page,
  pageIdx,
  theme,
  renderWidth,
  highlights,
  images = [],
  onSelectionCapture,
  register,
  active = true,
  virtualized = false,
}) {
  const rootRef = useRef(null);
  // renderWidth is the already-zoomed page box width, so the scale directly
  // maps PDF coords onto the box (text and box grow together — nothing clips).
  const scale = renderWidth / (page.width || 1);
  const fontFamily = theme.font;
  const color = theme.textColor;
  const cacheKey = `${pageSignature(page, pageIdx)}|${fontFamily}|${renderWidth}`;

  // Precompute global char offsets per run (concatenation, matching backend).
  const runs = (page.runs || []);
  let acc = 0;
  const annotated = runs.map((r) => {
    const start = acc;
    acc += r.t.length;
    return { ...r, start, end: acc };
  });
  const pageHighlights = highlights.get(pageIdx) || [];
  const inHighlight = (run) =>
    pageHighlights.some((h) => h.start < run.end && h.end > run.start);

  useLayoutEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    if (!active) return;
    const cached = fitCache.get(cacheKey);
    if (cached) {
      applyFitCache(el, cached);
      return;
    }
    let cancelled = false;
    (async () => {
      await ensureFontReady(fontFamily);
      if (cancelled) return;
      const sx = measureFit(el, fontFamily, renderWidth);
      if (cancelled) return;
      fitCache.set(cacheKey, sx);
      applyFitCache(el, sx);
    })();
    return () => {
      cancelled = true;
    };
  }, [cacheKey, fontFamily, active, renderWidth]);

  const handleSelection = () => {
    if (!onSelectionCapture) return;
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
    const range = sel.getRangeAt(0);
    const nodeSpan = (n) => {
      let el = n && n.nodeType === 3 ? n.parentElement : n;
      while (el && !el.classList?.contains("tl")) el = el.parentElement;
      return el;
    };
    const startEl = nodeSpan(range.startContainer);
    const endEl = nodeSpan(range.endContainer);
    if (!startEl || !endEl) return;
    const textNodeOf = (el) => {
      const node = el.firstChild;
      return node && node.nodeType === 3 ? node : null;
    };
    const startOff = range.startContainer === textNodeOf(startEl) ? range.startOffset : 0;
    const endOff = range.endContainer === textNodeOf(endEl) ? range.endOffset : (startEl.textContent || "").length;
    const startChar = parseInt(startEl.dataset.start) + startOff;
    const endChar = parseInt(endEl.dataset.start) + endOff;
    if (endChar <= startChar) return;
    const text = sel.toString().replace(/\s+/g, " ").trim();
    onSelectionCapture(pageIdx, startChar, endChar, text);
    sel.removeAllRanges();
  };

  // The page div must be tall enough for every run AND image, not just the
  // aspect ratio, or descending text / figures get clipped (overflow hidden).
  let contentBottom = 0;
  for (const r of runs) {
    contentBottom = Math.max(contentBottom, (r.y + r.fs) * scale);
  }
  for (const img of images) {
    contentBottom = Math.max(contentBottom, (img.y + img.h) * scale);
  }
  const aspectHeight = renderWidth * (page.height / page.width);
  const pageHeight = Math.max(aspectHeight, contentBottom + 10);

  return (
    <div
      ref={register}
      className="tl-page"
      data-page={pageIdx}
      style={{
        position: "relative",
        width: renderWidth,
        height: pageHeight,
        margin: "0 auto",
        background: theme.surface,
        boxShadow: "0 2px 14px rgba(63,56,39,0.14)",
        borderRadius: 6,
        overflow: "hidden",
        userSelect: "text",
        contentVisibility: virtualized ? "auto" : undefined,
        containIntrinsicSize: virtualized ? `${renderWidth}px ${pageHeight}px` : undefined,
      }}
      onMouseUp={handleSelection}
    >
      {images.map((img, i) => (
        <img
          key={i}
          src={img.url}
          alt=""
          draggable={false}
          style={{
            position: "absolute",
            left: img.x * scale,
            top: img.y * scale,
            width: img.w * scale,
            height: img.h * scale,
            objectFit: "fill",
            pointerEvents: "none",
          }}
        />
      ))}
      <div ref={rootRef} className="tl" style={{ position: "absolute", inset: 0, overflow: "hidden", lineHeight: 1 }}>
        {annotated.map((r, i) => {
          const hl = inHighlight(r);
          return (
            <span
              key={i}
              className={`tl${hl ? " hl" : ""}`}
              data-start={r.start}
              data-end={r.end}
              data-ow={r.w * scale}
              style={{
                position: "absolute",
                left: r.x * scale,
                top: (r.y - r.fs) * scale,
                fontSize: r.fs * scale,
                whiteSpace: "pre",
                transformOrigin: "0 0",
                transform: "scaleX(var(--sx, 1))",
                fontFamily,
                color,
                fontWeight: (r.flags & 16) ? 700 : 400,
                fontStyle: (r.flags & 2) ? "italic" : "normal",
                background: hl ? hexToRgba(pageHighlights.find((h) => h.start < r.end && h.end > r.start).color, 0.45) : undefined,
              }}
            >
              {r.t}
            </span>
          );
        })}
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 6,
          right: 10,
          fontSize: 11,
          opacity: 0.5,
          color: theme.textColor,
          pointerEvents: "none",
        }}
      >
        {pageIdx + 1}
      </div>
    </div>
  );
});

function hexToRgba(hex, alpha) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || "");
  if (!m) return `rgba(255,213,79,${alpha})`;
  const n = parseInt(m[1], 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}

// Scroll mode: a continuous vertical list of themed PDF-text pages.
export function TextLayerScrollView({ pages, theme, highlights, imagesByPage, onPageVisible, pageRefs, onSelectionCapture }) {
  const inset = insetPx(theme);
  const zoom = theme.zoom;
  const containerRef = useRef(null);
  const ioRef = useRef(null);
  const [availW, setAvailW] = useState(0);
  const [availH, setAvailH] = useState(0);
  const [visible, setVisible] = useState(() => new Set());

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const measure = () => {
      setAvailW(el.clientWidth);
      // The column grows with its content, so the visible height must come
      // from the scrolling parent (Reader's scrollRef).
      setAvailH(el.parentElement?.clientHeight || window.innerHeight);
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    window.addEventListener("resize", measure);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, []);

  // Only fit text (the expensive measure pass) for pages near the viewport;
  // offscreen pages skip layout entirely via content-visibility.
  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        setVisible((prev) => {
          const next = new Set(prev);
          let changed = false;
          for (const e of entries) {
            const idx = Number(e.target.dataset.page);
            if (e.isIntersecting) {
              if (!next.has(idx)) {
                next.add(idx);
                changed = true;
              }
            } else if (next.has(idx)) {
              next.delete(idx);
              changed = true;
            }
          }
          return changed ? next : prev;
        });
      },
      { rootMargin: "800px 0px" }
    );
    ioRef.current = io;
    return () => io.disconnect();
  }, []);

  // Stable callback so React.memo on PageSurface actually prevents re-renders
  // of every page when an unrelated page updates (scroll position, progress).
  const register = useCallback(
    (el) => {
      if (!el) return;
      const idx = Number(el.dataset.page);
      pageRefs.current[idx] = el;
      ioRef.current?.observe(el);
      onPageVisible?.(el, idx);
    },
    [pageRefs, ioRef, onPageVisible]
  );

  const renderWidth = Math.min(Math.max(availW - inset * 2, 280), SCROLL_MAX_WIDTH);

  // Per-page box width from the active zoom preset:
  //  - "width": fills the reading width (default), capped for line length.
  //  - "page":  fits the whole page within the viewport.
  //  - percent: natural PDF size (1pt = 1px) at that percentage.
  const boxWidthFor = (page) => {
    const pw = page.width || 1;
    const ph = page.height || 1;
    if (zoom === "page") {
      const scale = Math.min((availW - inset * 2) / pw, (availH - 48) / ph);
      return Math.max(80, pw * scale);
    }
    if (typeof zoom === "number") {
      return Math.max(60, pw * (zoom / 100));
    }
    return renderWidth;
  };

  return (
    <div
      ref={containerRef}
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 28,
        padding: `40px ${inset}px 120px`,
      }}
    >
      {pages.map((page, idx) => (
        <PageSurface
          key={idx}
          page={page}
          pageIdx={idx}
          theme={theme}
          renderWidth={boxWidthFor(page)}
          highlights={highlights}
          images={imagesByPage?.get(idx) || []}
          onSelectionCapture={onSelectionCapture}
          register={register}
          active={visible.has(idx)}
          virtualized
        />
      ))}
    </div>
  );
}

// Paginate mode: one page at a time (or a two-page spread), fit to the
// viewport, page-turn navigation. Spread mode flips by 2 (paired spreads).
export function TextLayerPaginateView({
  pages,
  theme,
  highlights,
  imagesByPage,
  page,
  onPageChange,
  onSelectionCapture,
  pageLayout = "single",
}) {
  const inset = insetPx(theme);
  const zoom = theme.zoom;
  const wrapRef = useRef(null);
  const [size, setSize] = useState({ w: 0, h: 0 });

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const measure = () =>
      setSize({ w: el.clientWidth, h: el.clientHeight });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    window.addEventListener("resize", measure);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, []);

  const spread = pageLayout === "spread";
  // In spread mode the current index is always the left page of a pair.
  const base = spread ? page - (page % 2) : page;
  const pg = pages[base];
  const pg2 = spread ? pages[base + 1] : null;

  let scale = 1;
  let renderWidth = 0;
  let renderWidth2 = 0;
  if (pg) {
    const maxH = size.h - 24;
    if (spread) {
      const gap = 24;
      const combinedW = pg.width + (pg2 ? pg2.width + gap : 0);
      if (zoom === "page") {
        scale = Math.min((size.w - inset * 2) / combinedW, maxH / Math.max(pg.height, pg2?.height || pg.height));
      } else if (typeof zoom === "number") {
        scale = zoom / 100;
      } else {
        scale = (size.w - inset * 2) / combinedW;
      }
      renderWidth = Math.max(80, pg.width * scale);
      renderWidth2 = pg2 ? Math.max(80, pg2.width * scale) : 0;
    } else {
      if (zoom === "page") {
        scale = Math.min((size.w - inset * 2) / pg.width, maxH / pg.height);
      } else if (typeof zoom === "number") {
        scale = zoom / 100;
      } else {
        scale = (size.w - inset * 2) / pg.width;
      }
      renderWidth = Math.max(80, pg.width * scale);
    }
  }

  const step = spread ? 2 : 1;
  const go = (dir) => {
    const n = base + dir * step;
    if (n >= 0 && n < pages.length) onPageChange(n);
  };

  // Stable no-op so the memoized PageSurface keeps its identity across renders.
  const noopRegister = useCallback(() => {}, []);

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") go(1);
      else if (e.key === "ArrowLeft" || e.key === "PageUp") go(-1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  if (!pg) return null;

  const canPrev = base > 0;
  const canNext = spread ? base + 2 < pages.length : base < pages.length - 1;

  return (
    <div
      ref={wrapRef}
      style={{ width: "100%", height: "100%", position: "relative", display: "flex", alignItems: "flex-start", justifyContent: "flex-start", overflow: "auto" }}
    >
      <div style={{ margin: "auto", display: "flex", alignItems: "center", justifyContent: "center", gap: spread ? 24 : 0, minWidth: 0 }}>
        <PageSurface
          page={pg}
          pageIdx={base}
          theme={theme}
          renderWidth={renderWidth}
          highlights={highlights}
          images={imagesByPage?.get(base) || []}
          onSelectionCapture={onSelectionCapture}
          register={noopRegister}
        />
        {pg2 && (
          <PageSurface
            page={pg2}
            pageIdx={base + 1}
            theme={theme}
            renderWidth={renderWidth2}
            highlights={highlights}
            images={imagesByPage?.get(base + 1) || []}
            onSelectionCapture={onSelectionCapture}
            register={noopRegister}
          />
        )}
      </div>
      <button
        className="btn-icon"
        onClick={() => go(-1)}
        disabled={!canPrev}
        style={{ position: "absolute", left: 8, top: "50%", transform: "translateY(-50%)", opacity: canPrev ? 1 : 0.3 }}
        title="Previous page"
      >
        <span className="icon">chevron_left</span>
      </button>
      <button
        className="btn-icon"
        onClick={() => go(1)}
        disabled={!canNext}
        style={{ position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)", opacity: canNext ? 1 : 0.3 }}
        title="Next page"
      >
        <span className="icon">chevron_right</span>
      </button>
    </div>
  );
}
