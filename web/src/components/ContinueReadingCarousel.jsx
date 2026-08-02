import React, { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { bookAccent, ensureReadable, useImageAccent } from "./Library";

const PITCH = 240; // px between queue slots
const ADVANCE_MS = 4000; // auto-advance dwell between books
const EASE = "cubic-bezier(0.22, 1, 0.36, 1)";

/**
 * Continue Reading — a parallax cover-flow that rotates automatically like a
 * circular queue. One book is featured at the center (full size, full opacity)
 * while the rest recede to both sides (scaled, dimmed, gently tilted). Every
 * few seconds the queue advances: the featured book slides out and the next one
 * wraps into the center, forever — no scroll reset, no restart. Each cover has
 * a parallax layer that drifts on its own axis and an ambient floating
 * animation, so the covers are always in motion. Browsable with drag, horizontal
 * wheel, or the arrows.
 */
export default function ContinueReadingCarousel({ books, bookProgress, extractionFor, location }) {
  const n = books.length;
  const [frontF, setFrontF] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [visible, setVisible] = useState(false);
  const dragRef = useRef(null);
  const suppressClickRef = useRef(false);
  const settleTimer = useRef(null);
  const ioRef = useRef(null);

  const viewportRef = useRef(null);

  const sectionRef = useCallback(
    (el) => {
      if (ioRef.current) {
        ioRef.current.disconnect();
        ioRef.current = null;
      }
      if (!el) return;
      const io = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting));
      io.observe(el);
      ioRef.current = io;
    },
    []
  );
  useEffect(() => () => ioRef.current?.disconnect(), []);

  useEffect(() => {
    setFrontF(0);
  }, [n]);

  const wrap = (f) => {
    if (n <= 0) return 0;
    let p = f % n;
    if (p < 0) p += n;
    return p;
  };

  // Signed distance from the featured book (continuous, so dragging scrubs
  // smoothly). Negative = left side, positive = right side.
  const dOf = (i, f) => {
    let p = i - f;
    p = ((p % n) + n) % n;
    return p <= n / 2 ? p : p - n;
  };

  const settle = () => setFrontF((f) => wrap(Math.round(f)));

  // Auto-advance the circular queue every few seconds (only while visible and
  // not being manually scrubbed).
  useEffect(() => {
    if (n <= 1 || dragging || !visible) return;
    const t = setInterval(() => setFrontF((f) => wrap(f + 1)), ADVANCE_MS);
    return () => clearInterval(t);
  }, [n, dragging, visible]);

  const advance = (dir) => setFrontF((f) => wrap(f + dir));

  const onPointerDown = (e) => {
    if (e.target.closest && e.target.closest(".cr-arrow")) return;
    dragRef.current = { startX: e.clientX, startF: frontF, captured: false };
    setDragging(true);
  };
  const onPointerMove = (e) => {
    const d = dragRef.current;
    if (!d) return;
    const dx = e.clientX - d.startX;
    if (!d.captured && e.pointerType === "mouse" && Math.abs(dx) > 6) {
      d.captured = true;
      suppressClickRef.current = true;
      viewportRef.current?.setPointerCapture?.(e.pointerId);
    }
    setFrontF((f) => wrap(d.startF - dx / PITCH));
  };
  const onPointerUp = () => {
    if (!dragRef.current) return;
    dragRef.current = null;
    setDragging(false);
    settle();
    window.setTimeout(() => {
      suppressClickRef.current = false;
    }, 0);
  };
  const onPointerCancel = () => {
    dragRef.current = null;
    setDragging(false);
    suppressClickRef.current = false;
  };
  const onClickCapture = (e) => {
    if (suppressClickRef.current) {
      e.preventDefault();
      e.stopPropagation();
    }
  };

  // Horizontal wheel (trackpad two-finger or Shift+scroll) scrubs the queue.
  useEffect(() => {
    const vp = viewportRef.current;
    if (!vp) return;
    const onWheel = (e) => {
      if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
      e.preventDefault();
      setFrontF((f) => wrap(f - e.deltaX / PITCH));
      clearTimeout(settleTimer.current);
      settleTimer.current = setTimeout(settle, 220);
    };
    vp.addEventListener("wheel", onWheel, { passive: false });
    return () => {
      vp.removeEventListener("wheel", onWheel);
      clearTimeout(settleTimer.current);
    };
  }, [n]);

  if (!books || books.length === 0) return null;

  const transition = dragging ? "none" : `transform 900ms ${EASE}, opacity 900ms ${EASE}`;

  return (
    <section ref={sectionRef}>
      <h2
        style={{
          fontFamily: "var(--font-display)",
          fontSize: 18,
          color: "var(--on-surface)",
          marginBottom: 16,
          display: "flex",
          alignItems: "center",
          gap: 8,
        }}
      >
        <span className="icon text-primary" style={{ fontSize: 20 }}>auto_stories</span>
        Continue Reading
      </h2>

      <div
        className="cr-viewport"
        ref={viewportRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerCancel}
        onClickCapture={onClickCapture}
      >
        <div className="cr-stage">
          {books.map((book, i) => {
            const d = dOf(i, frontF);
            const ad = Math.min(Math.abs(d), 4);
            const x = d * PITCH;
            const scale = 1 - ad * 0.14;
            const opacity = Math.max(0.28, 1 - ad * 0.22);
            const rotY = -d * 8;
            const z = 100 - Math.min(Math.round(ad), 90);
            const parallax = { tx: -d * 18, ty: -ad * 12, s: 1.15 };
            return (
              <QueueCard
                key={book.id}
                book={book}
                progress={bookProgress?.[book.id] || 0}
                extraction={
                  extractionFor
                    ? extractionFor(book)
                    : { status: book.extraction_status, progress: 0 }
                }
                location={location}
                dragging={dragging}
                transition={transition}
                style={{
                  zIndex: z,
                  opacity,
                  transform: `translateX(calc(-50% + ${x}px)) rotateY(${rotY}deg) scale(${scale})`,
                  transition,
                }}
                parallax={parallax}
              />
            );
          })}
        </div>

        {n > 1 && (
          <>
            <button className="cr-arrow cr-arrow-left" title="Previous book" onClick={() => advance(-1)}>
              <span className="icon" style={{ fontSize: 22 }}>chevron_left</span>
            </button>
            <button className="cr-arrow cr-arrow-right" title="Next book" onClick={() => advance(1)}>
              <span className="icon" style={{ fontSize: 22 }}>chevron_right</span>
            </button>
          </>
        )}
      </div>
    </section>
  );
}

function QueueCard({ book, progress, extraction, location, style, parallax, dragging, transition }) {
  const accent = ensureReadable(useImageAccent(book.cover_url, bookAccent(book)));
  const pct = book.extraction_status === "done" ? Math.round(progress) : extraction.progress;
  const cover = book.cover_url;

  return (
    <div className="cr-slot" style={style}>
      <Link
        to={`/read/${book.id}`}
        state={{ from: location?.pathname }}
        draggable={false}
        className="cr-card"
      >
        <div
          className="cr-cover-inner"
          style={{
            background: cover
              ? "var(--surface-container-low)"
              : `linear-gradient(150deg, ${accent} 0%, ${accent}cc 55%, #0d0f0d 140%)`,
          }}
        >
          <div
            className="cr-cover-parallax"
            style={{
              transform: `translate(${parallax.tx}px, ${parallax.ty}px) scale(${parallax.s})`,
              transition: dragging ? "none" : `transform 900ms ${EASE}`,
            }}
          >
            <div
              className="cr-cover-drift"
              style={cover ? { backgroundImage: `url(${cover})` } : undefined}
            />
          </div>
          {!cover && (
            <div className="cr-cover-fallback">
              <div className="cr-cover-fallback-title">
                {book.title.length > 50 ? book.title.slice(0, 50) + "…" : book.title}
              </div>
              <div className="cr-cover-fallback-author">{book.author || "Unknown author"}</div>
            </div>
          )}
        </div>

        <div className="cr-meta">
          <div className="cr-meta-title">{book.title}</div>
          <div className="cr-meta-author">{book.author || "Unknown author"}</div>
          <div className="progress-track">
            <div className="progress-fill" style={{ width: `${Math.max(0, Math.min(100, pct))}%` }} />
          </div>
          <div className="cr-meta-pct">
            {book.extraction_status === "done" ? `${pct}% complete` : `Extracting… ${pct}%`}
          </div>
        </div>
      </Link>
    </div>
  );
}
