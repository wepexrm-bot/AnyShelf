import React from "react";
import { useUiMode } from "../uiMode";

export default function UiModeToggle({ style }) {
  const [mode, , toggle] = useUiMode();
  return (
    <button
      className="btn-icon"
      title={mode === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      aria-label="Toggle light or dark mode"
      onClick={toggle}
      style={style}
    >
      <span className="icon" style={{ fontSize: 22 }}>
        {mode === "dark" ? "light_mode" : "dark_mode"}
      </span>
    </button>
  );
}
