import React, { useEffect, useRef, useState } from "react";
import { api } from "../api";

export const THEME_PRESETS = [
  { id: "light", label: "Light", background: "#fcf9f8", textColor: "#1b1c1c", surface: "#ffffff" },
  { id: "dark", label: "Dark", background: "#1b1c1c", textColor: "#e8e8e8", surface: "#262626" },
  { id: "sepia", label: "Sepia", background: "#f4ecd8", textColor: "#3b352b", surface: "#fdfbf6" },
  { id: "night", label: "Night", background: "#0f172a", textColor: "#cbd5e1", surface: "#1e293b" },
  { id: "paper", label: "Old Paper", background: "#efe5ce", textColor: "#433a2a", surface: "#f8f0dc" },
  { id: "modern", label: "Modern", background: "#fafafa", textColor: "#141414", surface: "#ffffff" },
  { id: "mint", label: "Mint", background: "#eaf4eb", textColor: "#1b2a1c", surface: "#ffffff" },
  { id: "rose", label: "Rose", background: "#faebed", textColor: "#2c1b1e", surface: "#ffffff" },
  { id: "ocean", label: "Ocean", background: "#e6eff7", textColor: "#1b2a3a", surface: "#f4f8fc" },
  { id: "forest", label: "Forest", background: "#e4efe3", textColor: "#1c2a20", surface: "#f2f8f1" },
];

export const FONT_OPTIONS = [  { id: "serif", label: "Serif", stack: "'Source Serif 4', Georgia, serif" },
  { id: "sans", label: "Sans", stack: "'Inter', system-ui, sans-serif" },
  { id: "dyslexic", label: "Dyslexic", stack: "'OpenDyslexic', 'Comic Sans MS', sans-serif" },
  { id: "lora", label: "Lora", stack: "'Lora', Georgia, serif" },
  { id: "merriweather", label: "Merriweather", stack: "'Merriweather', Georgia, serif" },
  { id: "garamond", label: "Garamond", stack: "'EB Garamond', Georgia, serif" },
  { id: "roboto", label: "Roboto", stack: "'Roboto', system-ui, sans-serif" },
  { id: "opensans", label: "Open Sans", stack: "'Open Sans', system-ui, sans-serif" },
  { id: "atkinson", label: "Atkinson", stack: "'Atkinson Hyperlegible', system-ui, sans-serif" },
  { id: "playfair", label: "Playfair", stack: "'Playfair Display', Georgia, serif" },
  { id: "ptserif", label: "PT Serif", stack: "'PT Serif', Georgia, serif" },
  { id: "crimson", label: "Crimson", stack: "'Crimson Text', Georgia, serif" },
  { id: "lato", label: "Lato", stack: "'Lato', system-ui, sans-serif" },
  { id: "poppins", label: "Poppins", stack: "'Poppins', system-ui, sans-serif" },
  { id: "nunito", label: "Nunito", stack: "'Nunito', system-ui, sans-serif" },
];


const MARGIN_OPTIONS = [
  { id: "small", label: "Small", inset: 48 },
  { id: "medium", label: "Medium", inset: 96 },
  { id: "large", label: "Large", inset: 144 },
];

// Zoom presets: fit the reading width, fit the whole page, or a percentage of
// the PDF's natural size. Client-side only (kept in localStorage) so the shared
// server `font_size` field keeps meaning for mobile.
const ZOOM_PRESETS = [
  { value: "width", label: "Fit Width", icon: "swap_horiz" },
  { value: "page", label: "Fit Page", icon: "crop_free" },
  { value: 50, label: "50%" },
  { value: 60, label: "60%" },
  { value: 75, label: "75%" },
  { value: 100, label: "100%" },
  { value: 125, label: "125%" },
  { value: 150, label: "150%" },
  { value: 200, label: "200%" },
];

function zoomIsActive(theme, preset) {
  return theme.zoom === preset.value || (theme.zoom == null && preset.value === "width");
}

export default function ThemeControls({ theme, setTheme, onClose }) {
  const [dirty, setDirty] = useState(false);
  const [fontOpen, setFontOpen] = useState(false);
  const fontMenuRef = useRef(null);

  const applyTheme = (patch) => {
    setTheme({ ...theme, ...patch });
    if ("zoom" in patch) {
      try {
        localStorage.setItem("reader_zoom", JSON.stringify(patch.zoom));
      } catch {}
    }
    setDirty(true);
  };

  useEffect(() => {
    const onDoc = (e) => {
      if (fontMenuRef.current && !fontMenuRef.current.contains(e.target)) setFontOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, []);

  useEffect(() => {
    if (!dirty) return;
    const timer = setTimeout(async () => {
      try {
        await api("/settings/", {
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
        });
      } catch {
        // settings persistence is best-effort in the reader
      }
    }, 400);
    return () => clearTimeout(timer);
  }, [theme, dirty]);

  const resetDefaults = async () => {
    const defaults = {
      themeId: "light",
      background: THEME_PRESETS[0].background,
      surface: THEME_PRESETS[0].surface,
      textColor: THEME_PRESETS[0].textColor,
      fontId: "serif",
      font: FONT_OPTIONS[0].stack,
      fontSize: 20,
      lineSpacing: 1.6,
      marginId: "medium",
      margins: 96,
      mode: "scroll",
      pageLayout: "single",
      zoom: "width",
      textMode: true,
    };
    setTheme(defaults);
    try {
      localStorage.removeItem("reader_zoom");
      localStorage.removeItem("reader_textmode");
    } catch {}
    setDirty(false);
    try {
      await api("/settings/", {
        method: "PUT",
        body: {
          theme: "light",
          font_family: "serif",
          font_size: 20,
          line_spacing: 1.6,
          margins: "medium",
          reading_mode: "scroll",
          page_layout: "single",
        },
      });
    } catch {
      // ignore
    }
  };

  const rowLabel = {
    fontSize: 12,
    textTransform: "uppercase",
    letterSpacing: 1,
    color: "var(--on-surface-variant)",
    fontWeight: 600,
    marginBottom: 10,
  };

  return (
    <aside
      className="settings-panel"
      style={{
        width: 320,
        height: "100%",
        background: "var(--surface-container-lowest)",
        borderLeft: "1px solid var(--outline-variant)",
        borderTopLeftRadius: 16,
        borderBottomLeftRadius: 16,
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
        flexShrink: 0,
        boxShadow: "-16px 0 40px rgba(0,0,0,0.18)",
      }}
    >
      <div
        style={{
          padding: "20px 24px",
          borderBottom: "1px solid var(--surface-variant)",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <h2 style={{ fontFamily: "var(--font-display)", fontSize: 20, margin: 0 }}>Reading Settings</h2>
        {onClose && (
          <button className="btn-icon" onClick={onClose}>
            <span className="icon">close</span>
          </button>
        )}
      </div>

      <div style={{ flex: 1, overflowY: "auto", padding: "24px 24px", display: "flex", flexDirection: "column", gap: 32 }}>
        {/* Theme */}
        <section>
          <div style={rowLabel}>Theme</div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12 }}>
            {THEME_PRESETS.map((preset) => {
              const active = theme.background === preset.background;
              return (
                <button
                  key={preset.id}
                  onClick={() => applyTheme({ themeId: preset.id, background: preset.background, surface: preset.surface, textColor: preset.textColor })}
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: 6,
                    background: "transparent",
                    border: "none",
                  }}
                >
                  <div
                    style={{
                      width: 40,
                      height: 40,
                      borderRadius: "50%",
                      background: preset.background,
                      border: active ? "2px solid var(--primary)" : "1px solid var(--outline-variant)",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      boxShadow: active ? "0 0 0 2px rgba(21,66,18,0.15)" : "0 1px 2px rgba(0,0,0,0.06)",
                    }}
                  >
                    {active && <span className="icon" style={{ color: "var(--primary)", fontSize: 16 }}>check</span>}
                  </div>
                  <span style={{ fontSize: 12, fontWeight: 500, color: active ? "var(--primary)" : "var(--on-surface-variant)" }}>
                    {preset.label}
                  </span>
                </button>
              );
            })}
          </div>
        </section>

        {/* Typography */}
        <section style={{ display: "flex", flexDirection: "column", gap: 20 }}>
          <div style={{ ...rowLabel, paddingBottom: 8, borderBottom: "1px solid var(--surface-variant)" }}>Typography</div>

          <div>
            <label style={{ fontSize: 12, color: "var(--on-surface-variant)", display: "block", marginBottom: 8 }}>
              Font Family
            </label>
            <div ref={fontMenuRef} style={{ position: "relative" }}>
              <button
                onClick={() => setFontOpen((o) => !o)}
                style={{
                  width: "100%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  gap: 10,
                  padding: "11px 14px",
                  borderRadius: 10,
                  border: "1px solid var(--outline-variant)",
                  background: "var(--surface)",
                  cursor: "pointer",
                  boxShadow: fontOpen ? "0 0 0 3px rgba(21,66,18,0.18)" : "none",
                }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
                  <span className="icon text-muted" style={{ fontSize: 17 }}>font_download</span>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontFamily: theme.font, fontSize: 14, color: "var(--on-surface)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                      {FONT_OPTIONS.find((f) => f.id === theme.fontId)?.label || "Default"}
                    </div>
                    <div style={{ fontFamily: theme.font, fontSize: 10, color: "var(--on-surface-variant)", opacity: 0.7, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                      The quick brown fox jumps over the lazy dog
                    </div>
                  </div>
                </div>
                <span className="icon text-muted" style={{ fontSize: 18, flexShrink: 0 }}>{fontOpen ? "expand_less" : "expand_more"}</span>
              </button>
              {fontOpen && (
                <div
                  style={{
                    position: "absolute",
                    top: "calc(100% + 6px)",
                    left: 0,
                    right: 0,
                    zIndex: 50,
                    maxHeight: 264,
                    overflowY: "auto",
                    padding: 6,
                    background: "var(--surface-container-lowest)",
                    border: "1px solid var(--outline-variant)",
                    borderRadius: 12,
                    boxShadow: "0 18px 44px rgba(0,0,0,0.22)",
                  }}
                >
                  {FONT_OPTIONS.map((f) => {
                    const active = theme.fontId === f.id;
                    return (
                      <button
                        key={f.id}
                        onClick={() => {
                          applyTheme({ fontId: f.id, font: f.stack });
                          setFontOpen(false);
                        }}
                        style={{
                          width: "100%",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "space-between",
                          gap: 10,
                          padding: "9px 12px",
                          borderRadius: 8,
                          border: "none",
                          background: active ? "rgba(21,66,18,0.08)" : "transparent",
                          color: active ? "var(--primary)" : "var(--on-surface)",
                          cursor: "pointer",
                          textAlign: "left",
                        }}
                      >
                        <div style={{ fontFamily: f.stack, fontSize: 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                          {f.label}
                        </div>
                        <div style={{ fontFamily: f.stack, fontSize: 10, color: "var(--on-surface-variant)", opacity: 0.7, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                          Aa The quick brown fox
                        </div>
                        {active && <span className="icon" style={{ fontSize: 15, flexShrink: 0 }}>check</span>}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>

          <div>
            <label style={{ fontSize: 12, color: "var(--on-surface-variant)", display: "block", marginBottom: 8 }}>
              Page Zoom
            </label>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              {ZOOM_PRESETS.map((p) => {
                const active = zoomIsActive(theme, p);
                const isPct = typeof p.value === "number";
                return (
                  <button
                    key={p.label}
                    onClick={() => applyTheme({ zoom: p.value })}
                    style={{
                      flex: isPct ? "1 1 30%" : "1 1 100%",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: 6,
                      padding: "7px 8px",
                      borderRadius: 6,
                      border: active ? "2px solid var(--primary)" : "1px solid var(--outline-variant)",
                      background: active ? "rgba(21,66,18,0.06)" : "transparent",
                      color: active ? "var(--primary)" : "var(--on-surface-variant)",
                      fontWeight: active ? 600 : 500,
                      fontSize: 12,
                    }}
                  >
                    {p.icon && <span className="icon" style={{ fontSize: 14 }}>{p.icon}</span>}
                    {p.label}
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        {/* Layout */}
        <section style={{ display: "flex", flexDirection: "column", gap: 20, borderTop: "1px solid var(--surface-variant)", paddingTop: 24 }}>
          <div>
            <label style={{ fontSize: 12, color: "var(--on-surface-variant)", display: "block", marginBottom: 8 }}>Page Margins</label>
            <div style={{ display: "flex", gap: 8 }}>
              {MARGIN_OPTIONS.map((m) => (
                <button
                  key={m.id}
                  onClick={() => applyTheme({ marginId: m.id, margins: m.inset })}
                  style={{
                    flex: 1,
                    padding: "8px 4px",
                    borderRadius: 6,
                    background: theme.marginId === m.id ? "rgba(21,66,18,0.06)" : "transparent",
                    border: theme.marginId === m.id ? "2px solid var(--primary)" : "1px solid var(--outline-variant)",
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: 6,
                  }}
                >
                  <div style={{ width: 36, height: 36, border: "1px solid var(--outline)", background: "var(--surface-container-low)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <div style={{ width: 36 - m.inset / 4, height: 26, background: "var(--surface-variant)" }} />
                  </div>
                  <span style={{ fontSize: 11, fontWeight: theme.marginId === m.id ? 600 : 500, color: theme.marginId === m.id ? "var(--primary)" : "var(--on-surface-variant)" }}>
                    {m.label}
                  </span>
                </button>
              ))}
            </div>
          </div>

          <div>
            <label style={{ fontSize: 12, color: "var(--on-surface-variant)", display: "block", marginBottom: 8 }}>Reading Mode</label>
            <div style={{ display: "flex", background: "var(--surface-container-low)", borderRadius: 8, padding: 4, border: "1px solid var(--outline-variant)" }}>
              {[
                { id: "scroll", label: "Scroll" },
                { id: "paginate", label: "Paginate" },
              ].map((mode) => (
                <button
                  key={mode.id}
                  onClick={() => applyTheme({ mode: mode.id })}
                  style={{
                    flex: 1,
                    padding: "8px 8px",
                    borderRadius: 6,
                    border: "none",
                    background: theme.mode === mode.id ? "var(--surface-container-lowest)" : "transparent",
                    color: theme.mode === mode.id ? "var(--primary)" : "var(--on-surface-variant)",
                    fontWeight: theme.mode === mode.id ? 600 : 500,
                    fontSize: 12,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: 6,
                  }}
                >
                  <span className="icon" style={{ fontSize: 15 }}>{mode.id === "scroll" ? "swap_vert" : "menu_book"}</span>
                  {mode.label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label style={{ fontSize: 12, color: "var(--on-surface-variant)", display: "block", marginBottom: 8 }}>Page Layout</label>
            <div style={{ display: "flex", background: "var(--surface-container-low)", borderRadius: 8, padding: 4, border: "1px solid var(--outline-variant)" }}>
              {[
                { id: "single", label: "Single Page" },
                { id: "spread", label: "Two Pages" },
              ].map((layout) => (
                <button
                  key={layout.id}
                  onClick={() => applyTheme({ pageLayout: layout.id })}
                  style={{
                    flex: 1,
                    padding: "8px 8px",
                    borderRadius: 6,
                    border: "none",
                    background: theme.pageLayout === layout.id ? "var(--surface-container-lowest)" : "transparent",
                    color: theme.pageLayout === layout.id ? "var(--primary)" : "var(--on-surface-variant)",
                    fontWeight: theme.pageLayout === layout.id ? 600 : 500,
                    fontSize: 12,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: 6,
                  }}
                >
                  <span className="icon" style={{ fontSize: 15 }}>{layout.id === "single" ? "description" : "auto_stories"}</span>
                  {layout.label}
                </button>
              ))}
            </div>
          </div>
        </section>
      </div>

      <div style={{ padding: 16, borderTop: "1px solid var(--surface-variant)", background: "var(--surface)" }}>
        <button className="btn btn-ghost btn-block" onClick={resetDefaults} style={{ fontSize: 13 }}>
          <span className="icon" style={{ fontSize: 16 }}>restart_alt</span>
          Reset to Defaults
        </button>
      </div>
    </aside>
  );
}
