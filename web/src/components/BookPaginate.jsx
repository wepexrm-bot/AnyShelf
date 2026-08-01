import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import HTMLFlipBook from "react-pageflip";

const LINE_SPACING = 1.6;
const PAGE_CACHE = new Map();

const ls = (theme) => theme.lineSpacing || LINE_SPACING;

function buildPages(stream, H, W, theme, headingFont) {
  const meas = document.createElement("div");
  Object.assign(meas.style, {
    position: "absolute",
    left: "-99999px",
    top: "0",
    width: `${W}px`,
    visibility: "hidden",
    whiteSpace: "normal",
    wordBreak: "break-word",
    boxSizing: "border-box",
    margin: "0",
  });
  document.body.appendChild(meas);

  const measure = (kind, text) => {
    if (!text) return 0;
    meas.textContent = text;
    meas.style.fontFamily = kind === "heading" ? headingFont : theme.font;
    meas.style.fontSize = `${kind === "heading" ? theme.fontSize * 1.45 : theme.fontSize}px`;
    meas.style.fontWeight = kind === "heading" ? "700" : "400";
    meas.style.lineHeight = kind === "heading" ? "1.3" : `${ls(theme)}`;
    return meas.getBoundingClientRect().height;
  };

  const paraGap = theme.fontSize * 1.1;
  const headingTop = theme.fontSize * 1.6;
  const headingBottom = theme.fontSize * 0.7;

  const maxText = (text, maxH, kind) => {
    if (measure(kind, text) <= maxH) return text;
    let lo = 0;
    let hi = text.length;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      if (measure(kind, text.slice(0, mid)) <= maxH) lo = mid;
      else hi = mid - 1;
    }
    let cut = text.slice(0, lo);
    if (cut && cut.length < text.length) {
      const sp = cut.lastIndexOf(" ");
      if (sp > 0) cut = cut.slice(0, sp);
    }
    return cut;
  };

  const pages = [];
  let blocks = [];
  let used = 0;

  const flush = () => {
    if (blocks.length) {
      pages.push({ blocks, used });
      blocks = [];
      used = 0;
    }
  };

  const add = (kind, text) => {
    const topM = blocks.length === 0 ? 0 : kind === "heading" ? headingTop : 0;
    const bottomM = kind === "heading" ? headingBottom : paraGap;
    const h = measure(kind, text);
    blocks.push({ kind, text, h, topM, bottomM });
    used += topM + h + bottomM;
  };

  for (const blk of stream) {
    const kind = blk.kind;
    const topM = blocks.length === 0 ? 0 : kind === "heading" ? headingTop : 0;
    const bottomM = kind === "heading" ? headingBottom : paraGap;
    const h = measure(kind, blk.text);

    if (used + topM + h + bottomM <= H) {
      add(kind, blk.text);
      continue;
    }

    flush();
    if (h + bottomM <= H) {
      add(kind, blk.text);
      continue;
    }

    flush();
    let remaining = blk.text;
    while (remaining) {
      const avail = Math.max(20, H - bottomM);
      let chunk = maxText(remaining, avail, kind);
      if (!chunk) break;
      if (kind === "heading" && chunk.indexOf(" ") === -1 && remaining.length > chunk.length) {
        const more = remaining.indexOf(" ", chunk.length);
        if (more !== -1) chunk = remaining.slice(0, more);
      }
      add(kind, chunk);
      remaining = remaining.slice(chunk.length).trimStart();
      if (remaining) flush();
    }
  }
  flush();

  for (let i = 0; i < pages.length - 1; i++) {
    const p = pages[i];
    const last = p.blocks[p.blocks.length - 1];
    if (last && last.kind === "heading") {
      const next = pages[i + 1];
      const extra = last.topM + last.h + last.bottomM;
      const addTop = next.blocks.length === 0 ? 0 : headingTop;
      if (next.used + extra <= H) {
        p.blocks.pop();
        p.used -= last.h + last.topM + last.bottomM;
        next.blocks.unshift(last);
        next.used += addTop + last.h + last.bottomM;
      }
    }
  }

  document.body.removeChild(meas);
  return pages.map((p) => p.blocks);
}

const paperFor = (themeId) =>
  themeId === "sepia"
    ? "#fbf5e9"
    : themeId === "dark"
    ? "#26262b"
    : themeId === "night"
    ? "#1e293b"
    : "#fffdfb";

export default function BookPaginate({ blocks, theme, initialProgress = 0, onPageChange, onPageCount, spread = false }) {
  const wrapRef = useRef(null);
  const flipRef = useRef(null);
  const [layout, setLayout] = useState(null);
  const [fontsReady, setFontsReady] = useState(false);
  const [pages, setPages] = useState(null);
  const [applying, setApplying] = useState(false);
  const [current, setCurrent] = useState(0);
  const [ready, setReady] = useState(false);
  const [jumpValue, setJumpValue] = useState("1");
  const [flipGen, setFlipGen] = useState(0);

  const resumeFractionRef = useRef(initialProgress > 0 ? initialProgress / 100 : null);

  const headingFont = useMemo(() => {
    let f = theme.font;
    try {
      const v = getComputedStyle(document.documentElement).getPropertyValue("--font-display").trim();
      if (v) f = v;
    } catch {}
    return f;
  }, [theme.font]);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const update = () => {
      const r = el.getBoundingClientRect();
      setLayout((prev) =>
        prev && Math.abs(prev.w - r.width) < 1 && Math.abs(prev.h - r.height) < 1 ? prev : { w: r.width, h: r.height }
      );
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    let mounted = true;
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(() => mounted && setFontsReady(true));
    } else {
      setFontsReady(true);
    }
    return () => {
      mounted = false;
    };
  }, []);

  const stream = useMemo(
    () =>
      (blocks || [])
        .map((b) => {
          const text = (b.text || "").replace(/\s+/g, " ").trim();
          return text ? { kind: b.kind === "heading" ? "heading" : "para", text } : null;
        })
        .filter(Boolean),
    [blocks]
  );

  const metrics = useMemo(() => {
    if (!layout || !fontsReady) return null;
    const controlsH = 64;
    const cardPadX = 56;
    const cardPadY = 44;
    const wide = spread ? layout.w >= 1000 : false;
    const cardH = Math.max(240, layout.h - controlsH - 24);
    const contentH = cardH - cardPadY * 2;
    const cardW = wide ? Math.max(320, Math.round((layout.w - 64) / 2)) : Math.min(layout.w - 32, 720);
    const textW = Math.max(200, cardW - cardPadX * 2);
    const bookW = wide ? cardW * 2 : cardW;
    return { wide, cardH, cardW, contentH, textW, bookW, cardPadX, cardPadY };
  }, [layout, fontsReady, spread]);

  const pageKey = metrics
    ? `${metrics.contentH}|${metrics.textW}|${theme.fontSize}|${ls(theme)}|${theme.font}|${headingFont}`
    : null;

  useEffect(() => {
    if (!pageKey || !metrics) return;
    if (stream.length === 0) {
      setPages([]);
      setApplying(false);
      return;
    }
    if (PAGE_CACHE.has(pageKey)) {
      setPages(PAGE_CACHE.get(pageKey));
      setApplying(false);
      return;
    }
    setApplying(true);
    const t = setTimeout(() => {
      const built = buildPages(stream, metrics.contentH, metrics.textW, theme, headingFont);
      PAGE_CACHE.set(pageKey, built);
      if (PAGE_CACHE.size > 16) {
        const oldest = PAGE_CACHE.keys().next().value;
        PAGE_CACHE.delete(oldest);
      }
      setPages(built);
      setApplying(false);
    }, 200);
    return () => clearTimeout(t);
  }, [pageKey, metrics, stream, theme, headingFont]);

  const N = pages ? pages.length : 0;

  useEffect(() => {
    if (onPageCount && N) onPageCount(N);
  }, [N, onPageCount]);

  const flipInstance = useCallback(() => flipRef.current && flipRef.current.pageFlip(), []);

  const flip = useCallback((method, arg) => {
    const fb = flipInstance();
    if (!fb) return;
    if (method === "next") fb.flipNext("top");
    else if (method === "prev") fb.flipPrev("top");
    else if (method === "page") fb.flip(arg, "top");
    else if (method === "turn") fb.turnToPage(arg);
  }, [flipInstance]);

  const onFlipEvent = useCallback(
    (e) => {
      const idx = e.data;
      setCurrent(idx);
      if (N > 1) resumeFractionRef.current = idx / (N - 1);
      if (onPageChange && N) onPageChange(idx, N);
    },
    [onPageChange, N]
  );

  const onInitEvent = useCallback(
    (e) => {
      setReady(true);
      setFlipGen((g) => g + 1);
      if (e && e.data && typeof e.data.page === "number") setCurrent(e.data.page);
    },
    []
  );

  const onUpdateEvent = useCallback(() => {
    const fb = flipInstance();
    if (fb) {
      const idx = fb.getCurrentPageIndex();
      setCurrent(idx);
      if (N > 1) resumeFractionRef.current = idx / (N - 1);
    }
  }, [flipInstance, N]);

  const jump = (raw) => {
    const n = parseInt(raw, 10);
    if (!n || !N) return;
    const clamped = Math.max(1, Math.min(N, n));
    setJumpValue(String(clamped));
    const target = 2 * Math.floor((clamped - 1) / 2);
    flip("page", target);
  };

  useEffect(() => {
    setJumpValue(String(current + 1));
  }, [current]);

  useEffect(() => {
    if (!ready || !pages || N === 0) return;
    const fb = flipInstance();
    if (!fb) return;
    const cur = fb.getCurrentPageIndex();
    const frac = resumeFractionRef.current;
    if (frac != null && frac >= 0 && frac <= 1) {
      const target = 2 * Math.floor(Math.min(N - 1, Math.max(0, Math.round(frac * (N - 1)))) / 2);
      if (cur !== target) flip("turn", target);
      return;
    }
    if (cur >= N) flip("turn", N - 1);
  }, [ready, flipGen, pages, N, flip, flipInstance]);

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "ArrowRight" || e.key === "PageDown") flip("next");
      else if (e.key === "ArrowLeft" || e.key === "PageUp") flip("prev");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [flip]);

  const paper = paperFor(theme.themeId);
  const controlsDisabled = !pages || N === 0;

  const pageElements = useMemo(() => {
    if (!pages || !metrics) return null;
    return pages.map((blocksList, i) => (
      // The outer div is the StPageFlip page item — the library overwrites its
      // inline styles on every draw, so all real styling lives on the inner div.
      <div key={i} className="book-leaf">
        <div
          style={{
            width: "100%",
            height: "100%",
            boxSizing: "border-box",
            padding: `${metrics.cardPadY}px ${metrics.cardPadX}px`,
            background: paper,
            color: theme.textColor,
            fontFamily: theme.font,
            fontSize: theme.fontSize,
            lineHeight: ls(theme),
            overflow: "hidden",
            display: "flex",
            flexDirection: "column",
            position: "relative",
          }}
        >
          {blocksList.map((b, bi) =>
            b.kind === "heading" ? (
              <h3
                key={bi}
                style={{
                  fontFamily: headingFont,
                  fontSize: theme.fontSize * 1.45,
                  fontWeight: 700,
                  margin: `${b.topM}px 0 ${b.bottomM}px`,
                  lineHeight: 1.3,
                  color: theme.textColor,
                }}
              >
                {b.text}
              </h3>
            ) : (
              <p key={bi} style={{ margin: `${b.topM}px 0 ${b.bottomM}px`, textAlign: "justify" }}>
                {b.text}
              </p>
            )
          )}
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              bottom: Math.max(10, metrics.cardPadY / 2 - 8),
              textAlign: "center",
              fontSize: 11,
              opacity: 0.5,
              letterSpacing: 0.5,
            }}
          >
            {i + 1}
          </div>
        </div>
      </div>
    ));
  }, [pages, theme, paper, headingFont, metrics]);

  return (
    <div ref={wrapRef} style={{ width: "100%", height: "100%", boxSizing: "border-box", display: "flex", flexDirection: "column", minHeight: 0 }}>
      <div style={{ flex: 1, minHeight: 0, display: "flex", alignItems: "center", justifyContent: "center", overflow: "hidden", position: "relative" }}>
        {!metrics || !pages ? (
          <div className="loading">Preparing pages…</div>
        ) : N === 0 ? (
          <div className="text-muted">No readable text found.</div>
        ) : (
          <>
            <div style={{ width: metrics.bookW, height: metrics.cardH, position: "relative" }}>
              {/* stacked page edges behind the open book */}
              {[3, 2, 1].map((k) => (
                <div
                  key={k}
                  style={{
                    position: "absolute",
                    right: k * 4,
                    bottom: k * 4,
                    width: metrics.cardW - 8,
                    height: metrics.cardH - 8,
                    background: paper,
                    border: "1px solid rgba(0,0,0,0.07)",
                    borderRadius: 10,
                    boxShadow: "0 1px 2px rgba(0,0,0,0.06)",
                  }}
                />
              ))}

              <div style={{ position: "relative", zIndex: 1, height: "100%" }}>
                <HTMLFlipBook
                  ref={flipRef}
                  key={metrics.wide ? "spread" : "single"}
                  width={metrics.cardW}
                  height={metrics.cardH}
                  flippingTime={700}
                  drawShadow
                  maxShadowOpacity={0.6}
                  showPageCorners
                  usePortrait={!metrics.wide}
                  startPage={0}
                  showCover={false}
                  onFlip={onFlipEvent}
                  onInit={onInitEvent}
                  onUpdate={onUpdateEvent}
                >
                  {pageElements}
                </HTMLFlipBook>
              </div>

              {/* gutter / spine shading on the spread */}
              {metrics.wide && (
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    bottom: 0,
                    left: "50%",
                    width: 44,
                    transform: "translateX(-50%)",
                    background:
                      "linear-gradient(to right, rgba(0,0,0,0) 0%, rgba(63,56,39,0.10) 45%, rgba(63,56,39,0.14) 55%, rgba(0,0,0,0) 100%)",
                    pointerEvents: "none",
                    zIndex: 5,
                  }}
                />
              )}
            </div>
          </>
        )}

        {applying && (
          <div
            style={{
              position: "absolute",
              top: 8,
              left: "50%",
              transform: "translateX(-50%)",
              fontSize: 11,
              letterSpacing: 0.4,
              background: "rgba(0,0,0,0.55)",
              color: "#fff",
              padding: "3px 10px",
              borderRadius: 999,
              zIndex: 10,
            }}
          >
            Applying settings…
          </div>
        )}
      </div>

      {/* controls */}
      <div style={{ height: 64, display: "flex", alignItems: "center", justifyContent: "center", gap: 16, flexShrink: 0 }}>
        <button
          className="btn btn-ghost"
          onClick={() => flip("prev")}
          disabled={controlsDisabled || current <= 0}
          style={controlsDisabled || current <= 0 ? { opacity: 0.4, cursor: "default" } : {}}
        >
          <span className="icon" style={{ fontSize: 18 }}>chevron_left</span>
          Previous
        </button>

        <div style={{ display: "flex", alignItems: "center", gap: 6, whiteSpace: "nowrap" }}>
          <span style={{ fontSize: 12, color: "var(--on-surface-variant)" }}>Page</span>
          <input
            type="number"
            min={1}
            max={N || 1}
            value={jumpValue}
            onChange={(e) => setJumpValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") e.currentTarget.blur();
            }}
            onBlur={() => jump(jumpValue)}
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
          <span style={{ fontSize: 12, color: "var(--on-surface-variant)" }}>
            of {N || "—"}
          </span>
        </div>

        <button
          className="btn btn-primary"
          onClick={() => flip("next")}
          disabled={controlsDisabled || current >= N - 1}
          style={controlsDisabled || current >= N - 1 ? { opacity: 0.4, cursor: "default" } : {}}
        >
          Next
          <span className="icon" style={{ fontSize: 18 }}>chevron_right</span>
        </button>
      </div>
    </div>
  );
}
