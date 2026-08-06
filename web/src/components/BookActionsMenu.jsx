import React, { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { api } from "../api";
import { Modal } from "./ShelfForm";
import { GENRES } from "./UploadModal";
import { SHELVES_CHANGED, useShelfModal } from "./ShelfModalContext";

const fieldInput = {
  width: "100%",
  padding: "12px 14px",
  borderRadius: 10,
  border: "1px solid var(--outline-variant)",
  background: "var(--surface-container-low)",
  color: "var(--on-surface)",
  outline: "none",
  fontSize: 14,
  fontFamily: "var(--font-ui)",
  boxSizing: "border-box",
  transition: "border-color 0.2s, box-shadow 0.2s",
};

function EditBookModal({ book, onClose, onSaved }) {
  const [title, setTitle] = useState(book.title || "");
  const [author, setAuthor] = useState(book.author || "");
  const [genre, setGenre] = useState(book.genre || "");
  const [coverUrl, setCoverUrl] = useState(book.cover_url || null);
  const [saving, setSaving] = useState(false);
  const coverRef = useRef(null);

  const onCover = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    if (coverUrl && coverUrl !== book.cover_url) URL.revokeObjectURL(coverUrl);
    setCoverUrl(URL.createObjectURL(f));
  };

  const save = async () => {
    if (!title.trim() || saving) return;
    setSaving(true);
    try {
      await api(`/books/${book.id}`, {
        method: "PUT",
        body: { title: title.trim(), author: author.trim(), genre: genre || null },
      });
      const file = coverRef.current?.files?.[0];
      if (file) {
        const fd = new FormData();
        fd.append("file", file);
        await api(`/books/${book.id}/cover`, { method: "PUT", formData: fd });
      }
      onSaved();
    } catch (err) {
      alert(err.message);
    } finally {
      setSaving(false);
    }
  };

  const genreOptions = GENRES.includes(genre) ? GENRES : [genre, ...GENRES].filter(Boolean);

  return (
    <Modal onClose={onClose}>
      <div className="shelf-dialog__header">
        <div>
          <div className="shelf-dialog__header-icon">
            <span className="icon" style={{ fontSize: 22 }}>edit</span>
          </div>
          <div className="shelf-dialog__title">Edit Book</div>
          <div className="shelf-dialog__subtitle">Update the name, author, genre or cover.</div>
        </div>
        <button className="btn-icon" onClick={onClose} title="Close">
          <span className="icon" style={{ fontSize: 20 }}>close</span>
        </button>
      </div>

      <div className="shelf-dialog__body">
        <div className="field">
          <label>Book name <span style={{ color: "var(--error)" }}>*</span></label>
          <input
            style={fieldInput}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. The Great Gatsby"
            autoFocus
            onFocus={(e) => e.target.select()}
          />
        </div>

        <div className="field">
          <label>Author</label>
          <input
            style={fieldInput}
            value={author}
            onChange={(e) => setAuthor(e.target.value)}
            placeholder="e.g. F. Scott Fitzgerald"
          />
        </div>

        <div className="field">
          <label>Genre</label>
          <select style={fieldInput} value={genre} onChange={(e) => setGenre(e.target.value)}>
            <option value="">Select a genre (optional)</option>
            {genreOptions.map((g) => (
              <option key={g} value={g}>{g}</option>
            ))}
          </select>
        </div>

        <div className="field">
          <label>Cover image</label>
          <label className="upload-zone" htmlFor="edit-book-cover-input" title="Upload cover image">
            {coverUrl ? (
              <img src={coverUrl} alt="Cover preview" />
            ) : (
              <>
                <span className="icon" style={{ fontSize: 26, color: "var(--primary)" }}>add_photo_alternate</span>
                <span className="upload-zone__text">Upload a cover image</span>
                <span style={{ fontSize: 12 }}>JPG or PNG</span>
              </>
            )}
          </label>
          <input
            ref={coverRef}
            id="edit-book-cover-input"
            type="file"
            accept="image/*"
            style={{ display: "none" }}
            onChange={onCover}
          />
        </div>
      </div>

      <div className="shelf-dialog__footer">
        <button className="btn btn-ghost" onClick={onClose} disabled={saving} style={{ fontSize: 14 }}>
          Cancel
        </button>
        <button
          className="btn btn-primary"
          onClick={save}
          disabled={saving || !title.trim()}
          style={{ fontSize: 14, padding: "12px 28px" }}
        >
          <span className="icon" style={{ fontSize: 17 }}>save</span>
          {saving ? "Saving…" : "Save changes"}
        </button>
      </div>
    </Modal>
  );
}

function ShelfPickerModal({ book, onClose, onChanged }) {
  const { openCreateShelf } = useShelfModal();
  const [shelves, setShelves] = useState([]);
  const [busy, setBusy] = useState(new Set());

  const load = async () => {
    setShelves(await api("/shelves/").catch(() => []));
  };

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    const onShelvesChanged = () => load();
    window.addEventListener(SHELVES_CHANGED, onShelvesChanged);
    return () => window.removeEventListener(SHELVES_CHANGED, onShelvesChanged);
  }, []);

  const toggle = async (shelf) => {
    if (busy.has(shelf.id)) return;
    const inShelf = shelf.book_ids?.includes(book.id);
    setBusy((p) => new Set(p).add(shelf.id));
    try {
      if (inShelf) {
        await api(`/shelves/${shelf.id}/books/${book.id}`, { method: "DELETE" });
      } else {
        await api(`/shelves/${shelf.id}/books/${book.id}`, { method: "POST" });
      }
      await load();
    } catch {
    } finally {
      setBusy((p) => {
        const n = new Set(p);
        n.delete(shelf.id);
        return n;
      });
    }
  };

  return (
    <Modal onClose={onClose} width={420}>
      <div className="shelf-dialog__header">
        <div>
          <div className="shelf-dialog__header-icon">
            <span className="icon" style={{ fontSize: 22 }}>shelves</span>
          </div>
          <div className="shelf-dialog__title">Add to shelf</div>
          <div className="shelf-dialog__subtitle">Choose which shelves this book belongs to.</div>
        </div>
        <button className="btn-icon" onClick={onClose} title="Close">
          <span className="icon" style={{ fontSize: 20 }}>close</span>
        </button>
      </div>

      <div className="shelf-dialog__body">
        {shelves.length === 0 ? (
          <div className="text-muted" style={{ fontSize: 13, padding: "10px 2px" }}>
            No shelves yet — create one to organize this book.
          </div>
        ) : (
          <div className="book-picker">
            {shelves.map((shelf) => {
              const inShelf = shelf.book_ids?.includes(book.id);
              return (
                <label
                  key={shelf.id}
                  className="book-row"
                  style={{ cursor: busy.has(shelf.id) ? "progress" : "pointer" }}
                >
                  <input
                    type="checkbox"
                    checked={inShelf}
                    disabled={busy.has(shelf.id)}
                    onChange={() => toggle(shelf)}
                  />
                  <span
                    className="book-row__thumb"
                    style={{
                      background: (shelf.color || "#154212") + "33",
                      border: "1px solid var(--outline-variant)",
                    }}
                  >
                    <span className="icon" style={{ fontSize: 16 }}>shelves</span>
                  </span>
                  <span className="book-row__title">{shelf.name}</span>
                  {inShelf && <span className="icon" style={{ fontSize: 18, color: "var(--primary)" }}>check</span>}
                </label>
              );
            })}
          </div>
        )}

        <button
          className="sidebar-link"
          onClick={openCreateShelf}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "10px 12px",
            fontSize: 14,
            width: "100%",
            textAlign: "left",
            borderTop: "1px solid var(--outline-variant)",
            marginTop: 12,
          }}
        >
          <span className="icon" style={{ fontSize: 16 }}>add</span>
          New shelf…
        </button>
      </div>

      <div className="shelf-dialog__footer">
        <button className="btn btn-ghost" onClick={onClose} style={{ fontSize: 14 }}>
          Close
        </button>
      </div>
    </Modal>
  );
}

export default function BookActionsMenu({ book, onChanged }) {
  const [open, setOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [shelfOpen, setShelfOpen] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    const onClick = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const del = async () => {
    if (!window.confirm(`Delete "${book.title}" permanently?`)) return;
    try {
      await api(`/books/${book.id}`, { method: "DELETE" });
      onChanged();
    } catch {}
  };

  const retry = async () => {
    if (retrying) return;
    setRetrying(true);
    try {
      await api(`/books/${book.id}/re-extract`, { method: "POST" });
      onChanged();
    } catch (err) {
      alert(err.message || "Could not retry extraction");
    } finally {
      setRetrying(false);
      setOpen(false);
    }
  };

  return (
    <div ref={ref} className="book-actions">
      <button
        className="book-actions__btn"
        title="Book options"
        onClick={() => setOpen((o) => !o)}
      >
        <span className="icon" style={{ fontSize: 20 }}>more_vert</span>
      </button>

      {open && (
        <div className="book-actions__menu">
          {book.extraction_status === "failed" && (
            <button
              className="book-actions__item"
              onClick={retry}
              disabled={retrying}
            >
              <span className="icon">refresh</span>
              {retrying ? "Retrying…" : "Retry extraction"}
            </button>
          )}
          <button
            className="book-actions__item"
            onClick={() => {
              setOpen(false);
              setEditOpen(true);
            }}
          >
            <span className="icon">edit</span>
            Edit details
          </button>
          <button
            className="book-actions__item"
            onClick={() => {
              setOpen(false);
              setShelfOpen(true);
            }}
          >
            <span className="icon">shelves</span>
            Add to shelf
          </button>
          <button
            className="book-actions__item book-actions__item--danger"
            onClick={() => {
              setOpen(false);
              del();
            }}
          >
            <span className="icon">delete</span>
            Delete book
          </button>
        </div>
      )}

      {editOpen &&
        createPortal(
          <EditBookModal
            book={book}
            onClose={() => setEditOpen(false)}
            onSaved={() => {
              setEditOpen(false);
              onChanged();
            }}
          />,
          document.body
        )}
      {shelfOpen &&
        createPortal(
          <ShelfPickerModal book={book} onClose={() => setShelfOpen(false)} onChanged={onChanged} />,
          document.body
        )}
    </div>
  );
}
