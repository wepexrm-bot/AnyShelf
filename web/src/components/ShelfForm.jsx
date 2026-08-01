import React, { useRef, useState } from "react";
import { api } from "../api";

export const COLOR_PALETTE = [
  "#154212",
  "#2d5a27",
  "#00695c",
  "#283593",
  "#5c6bc0",
  "#8e24aa",
  "#c2185b",
  "#d84315",
  "#4e342e",
  "#546e7a",
];

export function coverStyle(shelf) {
  if (shelf.banner_url) {
    return { backgroundImage: `url(${shelf.banner_url})`, backgroundSize: "cover", backgroundPosition: "center" };
  }
  const c = shelf.color || COLOR_PALETTE[0];
  return { background: `linear-gradient(155deg, ${c} 0%, ${c}99 55%, #0d0f0d 135%)` };
}

export function Modal({ onClose, children, width = 520 }) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-card" style={{ maxWidth: width }} onClick={(e) => e.stopPropagation()}>
        {children}
      </div>
    </div>
  );
}

const inputBase = {
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

function hexToRgb(hex) {
  const cleaned = (hex || "#000000").replace("#", "");
  const full = cleaned.length === 3 ? cleaned.split("").map((c) => c + c).join("") : cleaned;
  const num = parseInt(full, 16);
  return { r: (num >> 16) & 255, g: (num >> 8) & 255, b: num & 255 };
}

function rgbToHsv(r, g, b) {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d !== 0) {
    switch (max) {
      case r: h = ((g - b) / d) % 6; break;
      case g: h = (b - r) / d + 2; break;
      default: h = (r - g) / d + 4;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  return { h, s: max === 0 ? 0 : (d / max) * 100, v: max * 100 };
}

function hsvToRgb(h, s, v) {
  h = ((h % 360) + 360) % 360;
  s /= 100;
  v /= 100;
  const c = v * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = v - c;
  let r = 0, g = 0, b = 0;
  if (h < 60) { r = c; g = x; }
  else if (h < 120) { r = x; g = c; }
  else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; }
  else if (h < 300) { r = x; b = c; }
  else { r = c; b = x; }
  return { r: Math.round((r + m) * 255), g: Math.round((g + m) * 255), b: Math.round((b + m) * 255) };
}

function hsvToHex(h, s, v) {
  const { r, g, b } = hsvToRgb(h, s, v);
  return "#" + [r, g, b].map((n) => n.toString(16).padStart(2, "0")).join("");
}

function hexToHsv(hex) {
  const { r, g, b } = hexToRgb(hex);
  return rgbToHsv(r, g, b);
}

function CustomColorPicker({ value, onChange }) {
  const [hsv, setHsv] = useState(() => hexToHsv(value));
  const [hex, setHex] = useState(value.toUpperCase());
  const svRef = useRef(null);
  const hueRef = useRef(null);

  const apply = (h, s, v) => {
    setHsv({ h, s, v });
    const c = hsvToHex(h, s, v);
    onChange(c);
    setHex(c.toUpperCase());
  };

  const startDrag = (handler) => (e) => {
    handler(e);
    const move = (ev) => handler(ev);
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const handleSv = (e) => {
    const rect = svRef.current.getBoundingClientRect();
    const x = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
    const y = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height));
    apply(hsv.h, x * 100, (1 - y) * 100);
  };

  const handleHue = (e) => {
    const rect = hueRef.current.getBoundingClientRect();
    const x = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
    apply(x * 360, hsv.s, hsv.v);
  };

  const onHexChange = (e) => {
    const val = e.target.value;
    setHex(val);
    const cleaned = /^#?[0-9a-f]{3}$/i.test(val)
      ? "#" + val.replace("#", "").split("").map((c) => c + c).join("")
      : /^#?[0-9a-f]{6}$/i.test(val)
      ? (val.startsWith("#") ? val : "#" + val)
      : null;
    if (cleaned) {
      const { h, s, v } = hexToHsv(cleaned);
      setHsv({ h, s, v });
      onChange(cleaned);
    }
  };

  const hueGradient = "linear-gradient(to right, hsl(0,100%,50%), hsl(60,100%,50%), hsl(120,100%,50%), hsl(180,100%,50%), hsl(240,100%,50%), hsl(300,100%,50%), hsl(360,100%,50%))";
  const svGradient = `linear-gradient(to top, #000, rgba(0,0,0,0)), linear-gradient(to right, #fff, hsl(${hsv.h},100%,50%))`;
  const handleColor = hsvToHex(hsv.h, 100, 100);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12, marginTop: 10 }}>
      <div
        ref={svRef}
        onPointerDown={startDrag(handleSv)}
        style={{
          position: "relative",
          height: 120,
          borderRadius: 12,
          cursor: "crosshair",
          background: svGradient,
          border: "1px solid var(--outline-variant)",
          touchAction: "none",
        }}
      >
        <div
          style={{
            position: "absolute",
            left: `${hsv.s}%`,
            top: `${100 - hsv.v}%`,
            width: 18,
            height: 18,
            borderRadius: "50%",
            border: "2px solid #fff",
            background: handleColor,
            boxShadow: "0 0 0 1px rgba(0,0,0,0.4), 0 2px 6px rgba(0,0,0,0.3)",
            transform: "translate(-50%,-50%)",
            pointerEvents: "none",
          }}
        />
      </div>

      <div
        ref={hueRef}
        onPointerDown={startDrag(handleHue)}
        style={{
          position: "relative",
          height: 16,
          borderRadius: 999,
          cursor: "ew-resize",
          background: hueGradient,
          border: "1px solid var(--outline-variant)",
          touchAction: "none",
        }}
      >
        <div
          style={{
            position: "absolute",
            left: `${(hsv.h / 360) * 100}%`,
            top: "50%",
            width: 20,
            height: 20,
            borderRadius: "50%",
            border: "2px solid #fff",
            background: handleColor,
            boxShadow: "0 0 0 1px rgba(0,0,0,0.4)",
            transform: "translate(-50%,-50%)",
            pointerEvents: "none",
          }}
        />
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: 10,
            background: value,
            border: "1px solid var(--outline-variant)",
            boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.25)",
            flexShrink: 0,
          }}
        />
        <div style={{ position: "relative", flex: 1 }}>
          <span style={{ position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)", color: "var(--on-surface-variant)", fontSize: 13, fontWeight: 600 }}>
            #
          </span>
          <input
            value={hex.replace(/^#/, "")}
            onChange={onHexChange}
            spellCheck={false}
            style={{
              width: "100%",
              padding: "9px 12px 9px 27px",
              borderRadius: 10,
              border: "1px solid var(--outline-variant)",
              background: "var(--surface-container-low)",
              color: "var(--on-surface)",
              outline: "none",
              fontSize: 13,
              fontFamily: "var(--font-ui)",
              textTransform: "uppercase",
              letterSpacing: "0.05em",
            }}
          />
        </div>
      </div>
    </div>
  );
}

export default function ShelfForm({ initial, books, onClose, onSaved }) {
  const [name, setName] = useState(initial?.name || "");
  const [description, setDescription] = useState(initial?.description || "");
  const [color, setColor] = useState(initial?.color || COLOR_PALETTE[0]);
  const initialBookIds = initial?.book_ids || initial?.books?.map((b) => b.id) || [];
  const [selected, setSelected] = useState(() => new Set(initialBookIds.map(String)));
  const [previewUrl, setPreviewUrl] = useState(initial?.banner_url || null);
  const [showCustom, setShowCustom] = useState(false);
  const [saving, setSaving] = useState(false);
  const fileRef = useRef(null);

  const toggleBook = (id) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const onFileChange = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (previewUrl && previewUrl !== initial?.banner_url) URL.revokeObjectURL(previewUrl);
    setPreviewUrl(URL.createObjectURL(file));
  };

  const save = async () => {
    if (!name.trim()) return;
    setSaving(true);
    try {
      let shelfId;
      if (initial) {
        const r = await api(`/shelves/${initial.id}`, {
          method: "PUT",
          body: { name: name.trim(), description: description.trim() || null, color },
        });
        shelfId = r.id;
      } else {
        const r = await api("/shelves/", {
          method: "POST",
          body: { name: name.trim(), description: description.trim() || null, color },
        });
        shelfId = r.id;
      }

      const file = fileRef.current?.files?.[0];
      if (file) {
        const fd = new FormData();
        fd.append("file", file);
        await api(`/shelves/${shelfId}/banner`, { method: "POST", formData: fd });
      }

      await Promise.all(
        books.map(async (b) => {
          const inShelf = selected.has(String(b.id));
          const inOld = initialBookIds.includes(b.id);
          if (inShelf && !inOld) {
            await api(`/shelves/${shelfId}/books/${b.id}`, { method: "POST" });
          } else if (!inShelf && inOld) {
            await api(`/shelves/${shelfId}/books/${b.id}`, { method: "DELETE" });
          }
        })
      );

      onSaved();
    } catch {
      alert("Could not save the shelf.");
    } finally {
      setSaving(false);
    }
  };

  const previewShelf = previewUrl ? { banner_url: previewUrl } : { color };

  return (
    <Modal onClose={onClose}>
      <div className="shelf-dialog__header">
        <div>
          <div className="shelf-dialog__header-icon">
            <span className="icon" style={{ fontSize: 22 }}>{initial ? "edit" : "add"}</span>
          </div>
          <div className="shelf-dialog__title">{initial ? "Edit Shelf" : "Create New Shelf"}</div>
          <div className="shelf-dialog__subtitle">
            {initial ? "Personalize this shelf's look and books." : "Name it, pick a color, and add a cover."}
          </div>
        </div>
        <button className="btn-icon" onClick={onClose} title="Close">
          <span className="icon" style={{ fontSize: 20 }}>close</span>
        </button>
      </div>

      <div className="shelf-dialog__body">
        {/* Live preview */}
        <div className="shelf-preview" style={coverStyle(previewShelf)}>
          <div className="shelf-preview__name">{name.trim() || "Shelf name"}</div>
        </div>

        {/* Name */}
        <div className="field">
          <label>Name</label>
          <input
            style={inputBase}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Sci-Fi Favorites"
            autoFocus
            onFocus={(e) => e.target.select()}
          />
        </div>

        {/* Description */}
        <div className="field">
          <label>Description</label>
          <textarea
            style={{ ...inputBase, minHeight: 64, resize: "none", lineHeight: 1.5 }}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="What's this shelf about?"
          />
        </div>

        {/* Color */}
        <div className="field">
          <label>Color</label>
          <div className="color-swatches">
            {COLOR_PALETTE.map((c) => (
              <button
                key={c}
                className={`color-swatch${color === c ? " selected" : ""}`}
                onClick={() => setColor(c)}
                aria-label={c}
                style={{ background: c }}
              >
                <span className="icon">check</span>
              </button>
            ))}
          </div>

          <div style={{ marginTop: 10 }}>
            <button
              onClick={() => setShowCustom((s) => !s)}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                width: "100%",
                padding: "11px 14px",
                borderRadius: 12,
                border: showCustom ? "2px solid var(--primary)" : "1px solid var(--outline-variant)",
                background: showCustom ? "rgba(21, 66, 18, 0.07)" : "var(--surface-container-low)",
                cursor: "pointer",
                transition: "border-color 0.2s, background-color 0.2s",
                color: "var(--on-surface)",
              }}
            >
              <span
                style={{
                  width: 22,
                  height: 22,
                  borderRadius: 8,
                  flexShrink: 0,
                  background:
                    showCustom || !COLOR_PALETTE.includes(color)
                      ? color
                      : "conic-gradient(red, yellow, lime, cyan, blue, magenta, red)",
                  border: "1px solid var(--outline-variant)",
                  boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.25)",
                }}
              />
              <span style={{ fontSize: 13, fontWeight: 600 }}>Custom color</span>
              <span
                className="icon"
                style={{
                  marginLeft: "auto",
                  fontSize: 18,
                  color: "var(--on-surface-variant)",
                  transition: "transform 0.2s",
                  transform: showCustom ? "rotate(180deg)" : "rotate(0deg)",
                }}
              >
                expand_more
              </span>
            </button>

            {showCustom && <CustomColorPicker value={color} onChange={setColor} />}
          </div>
        </div>

        {/* Cover image */}
        <div className="field">
          <label>Cover image</label>
          <label className="upload-zone" htmlFor="shelf-cover-input" title="Upload cover image">
            {previewUrl ? (
              <img src={previewUrl} alt="Cover preview" />
            ) : (
              <>
                <span className="icon" style={{ fontSize: 26, color: "var(--primary)" }}>add_photo_alternate</span>
                <span className="upload-zone__text">Upload a cover image</span>
                <span style={{ fontSize: 12 }}>JPG or PNG, optional</span>
              </>
            )}
          </label>
          <input
            ref={fileRef}
            id="shelf-cover-input"
            type="file"
            accept="image/*"
            style={{ display: "none" }}
            onChange={onFileChange}
          />
        </div>

        {/* Books */}
        <div className="field">
          <label>Books in this shelf ({selected.size})</label>
          <div className="book-picker">
            {books.length === 0 ? (
              <div className="text-muted" style={{ fontSize: 13, padding: 10 }}>
                No books uploaded yet — add them later from the shelf.
              </div>
            ) : (
              books.map((b) => (
                <label key={b.id} className="book-row">
                  <input type="checkbox" checked={selected.has(String(b.id))} onChange={() => toggleBook(String(b.id))} />
                  <span className="book-row__thumb">
                    <span className="icon" style={{ fontSize: 16 }}>auto_stories</span>
                  </span>
                  <span className="book-row__title">{b.title}</span>
                </label>
              ))
            )}
          </div>
        </div>
      </div>

      <div className="shelf-dialog__footer">
        <button className="btn btn-ghost" onClick={onClose} disabled={saving} style={{ fontSize: 14 }}>
          Cancel
        </button>
        <button className="btn btn-primary" onClick={save} disabled={saving || !name.trim()} style={{ fontSize: 14, padding: "12px 28px" }}>
          <span className="icon" style={{ fontSize: 17 }}>{initial ? "save" : "add"}</span>
          {saving ? "Saving…" : initial ? "Save changes" : "Create shelf"}
        </button>
      </div>
    </Modal>
  );
}
