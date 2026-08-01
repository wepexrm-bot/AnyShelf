import { useCallback, useEffect, useState } from "react";

const STORAGE_KEY = "cloudread_ui_mode";

export function getUiMode() {
  try {
    return localStorage.getItem(STORAGE_KEY) === "dark" ? "dark" : "light";
  } catch {
    return "light";
  }
}

export function applyUiMode(mode) {
  const root = document.documentElement;
  if (mode === "dark") root.setAttribute("data-theme", "dark");
  else root.removeAttribute("data-theme");
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", mode === "dark" ? "#121412" : "#fcf9f8");
}

export function useUiMode() {
  const [mode, setMode] = useState(getUiMode);

  useEffect(() => {
    applyUiMode(mode);
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {}
  }, [mode]);

  const changeMode = useCallback((next) => {
    setMode(next === "dark" ? "dark" : "light");
  }, []);

  const toggle = useCallback(() => {
    setMode((m) => (m === "dark" ? "light" : "dark"));
  }, []);

  return [mode, changeMode, toggle];
}
