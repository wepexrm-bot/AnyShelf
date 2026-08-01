import React, { useRef, useState } from "react";
import { api } from "../api";
import { Modal } from "./ShelfForm";

export const GENRES = [
  "Fiction",
  "Literary Fiction",
  "Classics",
  "Contemporary",
  "Romance",
  "Fantasy",
  "Science Fiction",
  "Dystopian",
  "Mystery",
  "Crime",
  "Thriller",
  "Suspense",
  "Horror",
  "Gothic",
  "Historical Fiction",
  "Adventure",
  "Western",
  "Young Adult",
  "New Adult",
  "Children's",
  "Middle Grade",
  "Picture Book",
  "Graphic Novel",
  "Comics",
  "Manga",
  "Poetry",
  "Drama",
  "Short Stories",
  "Essays",
  "Anthology",
  "Biography",
  "Autobiography",
  "Memoir",
  "Travel",
  "Food & Cooking",
  "Self-Help",
  "Personal Development",
  "Psychology",
  "Philosophy",
  "Religion",
  "Spirituality",
  "Mythology",
  "Fairy Tales",
  "Folklore",
  "Satire",
  "Humor",
  "Science",
  "History",
  "Politics",
  "Economics",
  "Business",
  "Technology",
  "Nature",
  "True Crime",
  "Sports",
  "Music",
  "Art",
  "Health & Fitness",
  "Education",
  "Reference",
  "Non-Fiction",
  "Other",
];

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

export default function UploadModal({ file, fileName, onClose, onUploaded }) {
  const [title, setTitle] = useState(fileName ? fileName.replace(/\.pdf$/i, "") : "");
  const [author, setAuthor] = useState("");
  const [genre, setGenre] = useState("");
  const [pdf, setPdf] = useState(file || null);
  const [pdfName, setPdfName] = useState(fileName || null);
  const [coverUrl, setCoverUrl] = useState(null);
  const [saving, setSaving] = useState(false);
  const coverRef = useRef(null);
  const pdfRef = useRef(null);

  const onPdf = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setPdf(f);
    setPdfName(f.name);
    if (!title) setTitle(f.name.replace(/\.pdf$/i, ""));
  };

  const onCover = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    if (coverUrl) URL.revokeObjectURL(coverUrl);
    setCoverUrl(URL.createObjectURL(f));
  };

  const submit = async () => {
    if (!pdf || !title.trim() || !author.trim() || saving) return;
    setSaving(true);
    try {
      const fd = new FormData();
      fd.append("file", pdf);
      fd.append("title", title.trim());
      fd.append("author", author.trim());
      if (genre) fd.append("genre", genre);
      const coverFile = coverRef.current?.files?.[0];
      if (coverFile) fd.append("cover", coverFile);
      const res = await api("/books/upload", { method: "POST", formData: fd });
      onUploaded(res);
    } catch (err) {
      alert(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal onClose={onClose}>
      <div className="shelf-dialog__header">
        <div>
          <div className="shelf-dialog__header-icon">
            <span className="icon" style={{ fontSize: 22 }}>upload_file</span>
          </div>
          <div className="shelf-dialog__title">Upload PDF</div>
          <div className="shelf-dialog__subtitle">
            Give your book a name, author and genre — many PDFs come with unclear filenames.
          </div>
        </div>
        <button className="btn-icon" onClick={onClose} title="Close">
          <span className="icon" style={{ fontSize: 20 }}>close</span>
        </button>
      </div>

      <div className="shelf-dialog__body">
        <div className="field">
          <label>PDF file <span style={{ color: "var(--error)" }}>*</span></label>
          {pdf ? (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                border: "1px solid var(--outline-variant)",
                borderRadius: 12,
                padding: "10px 14px",
                background: "var(--surface-container-low)",
              }}
            >
              <span className="icon" style={{ fontSize: 22, color: "var(--primary)" }}>picture_as_pdf</span>
              <span
                style={{
                  flex: 1,
                  fontSize: 14,
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                {pdfName}
              </span>
              <button
                type="button"
                className="btn btn-ghost"
                style={{ fontSize: 13, padding: "6px 12px" }}
                onClick={() => pdfRef.current?.click()}
              >
                Change
              </button>
            </div>
          ) : (
            <label className="upload-zone" htmlFor="book-pdf-input" title="Choose a PDF file">
              <span className="icon" style={{ fontSize: 26, color: "var(--primary)" }}>picture_as_pdf</span>
              <span className="upload-zone__text">Choose a PDF file</span>
              <span style={{ fontSize: 12 }}>Only PDF files are supported</span>
            </label>
          )}
          <input
            ref={pdfRef}
            id="book-pdf-input"
            type="file"
            accept="application/pdf"
            style={{ display: "none" }}
            onChange={onPdf}
          />
        </div>

        <div className="field">
          <label>Book name <span style={{ color: "var(--error)" }}>*</span></label>
          <input
            style={fieldInput}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. The Great Gatsby"
            autoFocus={!pdf}
          />
        </div>

        <div className="field">
          <label>Author <span style={{ color: "var(--error)" }}>*</span></label>
          <input
            style={fieldInput}
            value={author}
            onChange={(e) => setAuthor(e.target.value)}
            placeholder="e.g. F. Scott Fitzgerald"
            onKeyDown={(e) => {
              if (e.key === "Enter") submit();
            }}
          />
        </div>

        <div className="field">
          <label>Genre</label>
          <select
            style={fieldInput}
            value={genre}
            onChange={(e) => setGenre(e.target.value)}
          >
            <option value="">Select a genre (optional)</option>
            {GENRES.map((g) => (
              <option key={g} value={g}>{g}</option>
            ))}
          </select>
        </div>

        <div className="field">
          <label>Cover image <span style={{ color: "var(--on-surface-variant)", fontSize: 12 }}>optional</span></label>
          <label className="upload-zone" htmlFor="book-cover-input" title="Upload cover image">
            {coverUrl ? (
              <img src={coverUrl} alt="Cover preview" />
            ) : (
              <>
                <span className="icon" style={{ fontSize: 26, color: "var(--primary)" }}>add_photo_alternate</span>
                <span className="upload-zone__text">Upload a cover image</span>
                <span style={{ fontSize: 12 }}>JPG or PNG, optional</span>
              </>
            )}
          </label>
          <input
            ref={coverRef}
            id="book-cover-input"
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
          onClick={submit}
          disabled={saving || !pdf || !title.trim() || !author.trim()}
          style={{ fontSize: 14, padding: "12px 28px" }}
        >
          <span className="icon" style={{ fontSize: 17 }}>upload_file</span>
          {saving ? "Uploading…" : "Upload"}
        </button>
      </div>
    </Modal>
  );
}
