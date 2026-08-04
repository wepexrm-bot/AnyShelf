import React, { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { bookAccent, ensureReadable, useImageAccent } from "./Library";

const ADVANCE_MS = 4500; // auto-rotation dwell between books
const EASE = "cubic-bezier(0.22, 1, 0.36, 1)";

/**
 * Continue Reading — a featured hero card for the book you're mid-way through:
 * cover panel on the left, position/progress and actions on the right. It
 * auto-rotates through the queue in a shuffled order every few seconds (paused
 * on hover, or while off-screen) and can be cycled manually with the arrow.
 */
export default function ContinueReadingCarousel({ books, bookProgress, extractionFor, location }) {
  const [index, setIndex] = useState(0);
  const [hovering, setHovering] = useState(false);
  const [visible, setVisible] = useState(false);
  const ioRef = useRef(null);
  const n = books.length;

  useEffect(() => {
    setIndex(0);
  }, [n]);

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

  const book = n > 0 ? books[index % n] : null;
  const accent = ensureReadable(
    useImageAccent(book?.cover_url, bookAccent(book || { title: "", author: "" }))
  );

  // Auto-rotate in a shuffled order — never repeat the same book twice in a
  // row — while the section is on screen and not being hovered.
  useEffect(() => {
    if (n <= 1 || hovering || !visible) return;
    const t = setInterval(() => {
      setIndex((i) => {
        let r;
        do {
          r = Math.floor(Math.random() * n);
        } while (r === i);
        return r;
      });
    }, ADVANCE_MS);
    return () => clearInterval(t);
  }, [n, hovering, visible]);

  if (!book) return null;

  const progress = bookProgress?.[book.id] || 0;
  const extraction = extractionFor
    ? extractionFor(book)
    : { status: book.extraction_status, progress: 0 };

  const pct = book.extraction_status === "done" ? Math.round(progress) : extraction.progress;
  const clamped = Math.max(0, Math.min(100, pct));
  const cover = book.cover_url;
  const genre = book.genre || (book.is_scanned ? "Scanned" : "AnyShelf");
  const author = book.author || "Unknown author";

  const next = () => setIndex((i) => (i + 1) % n);

  return (
    <section ref={sectionRef}>
      <h2 className="cr-hero-title">
        <span className="icon text-primary" style={{ fontSize: 20 }}>auto_stories</span>
        Continue Reading
      </h2>

      <div
        className="cr-hero-wrap"
        onMouseEnter={() => setHovering(true)}
        onMouseLeave={() => setHovering(false)}
      >
        <div className="cr-hero-card" key={book.id} style={{ animation: `cr-hero-in 0.5s ${EASE}` }}>
          <Link
            to={`/read/${book.id}`}
            state={{ from: location?.pathname }}
            className="cr-hero-cover-link"
          >
            <div
              className="cr-hero-cover"
              style={
                cover
                  ? { backgroundImage: `url(${cover})` }
                  : { background: `linear-gradient(150deg, ${accent} 0%, ${accent}cc 55%, #0d0f0d 140%)` }
              }
            >
              <div className="cr-hero-cover-overlay" />
              <span className="cr-hero-genre">{genre}</span>
              {!cover && (
                <div className="cr-hero-cover-fallback">
                  <div className="cr-hero-cover-fallback-title">{book.title}</div>
                  <div className="cr-hero-cover-fallback-author">{author}</div>
                </div>
              )}
            </div>
          </Link>

          <div className="cr-hero-body">
            <div>
              <div className="cr-hero-head">
                <h3 className="cr-hero-book-title">{book.title}</h3>
                <button className="btn-icon" title="Bookmark">
                  <span className="icon" style={{ fontSize: 22 }}>bookmark_add</span>
                </button>
              </div>
              <p className="cr-hero-excerpt">{author}</p>
              <p className="cr-hero-note">
                {book.extraction_status === "done"
                  ? `You're ${pct}% through this book — pick up right where you left off.`
                  : `Still extracting this book… ${pct}%`}
              </p>
            </div>

            <div className="cr-hero-footer">
              <div className="cr-hero-progress-row">
                <span>{pct}% Completed</span>
                {n > 1 && (
                  <span className="cr-hero-count">
                    {index + 1} of {n}
                  </span>
                )}
              </div>
              <div className="progress-track">
                <div className="progress-fill" style={{ width: `${clamped}%` }} />
              </div>
              <div className="cr-hero-actions">
                <Link
                  to={`/read/${book.id}`}
                  state={{ from: location?.pathname }}
                  className="btn btn-primary"
                >
                  <span className="icon" style={{ fontSize: 18 }}>menu_book</span>
                  Resume
                </Link>
                <Link
                  to={`/read/${book.id}`}
                  state={{ from: location?.pathname }}
                  className="btn btn-ghost"
                >
                  Notes
                </Link>
              </div>
            </div>
          </div>
        </div>

        {n > 1 && (
          <button className="cr-hero-arrow" title="Next book" onClick={next}>
            <span className="icon" style={{ fontSize: 22 }}>arrow_forward</span>
          </button>
        )}
      </div>
    </section>
  );
}
