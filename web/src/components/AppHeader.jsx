import React, { useEffect, useState } from "react";
import { useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { useAuth } from "../auth";
import UiModeToggle from "./UiModeToggle";

export default function AppHeader({ title, children }) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const [input, setInput] = useState(searchParams.get("q") || "");

  useEffect(() => {
    setInput(searchParams.get("q") || "");
  }, [location.search]);

  const liveFilter = location.pathname === "/" || location.pathname === "/books";
  const basePath = location.pathname === "/books" ? "/books" : "/";

  const onChange = (e) => {
    const v = e.target.value;
    setInput(v);
    if (liveFilter) {
      navigate(
        { pathname: basePath, search: v ? `?q=${encodeURIComponent(v)}` : "" },
        { replace: true }
      );
    }
  };

  const onKeyDown = (e) => {
    if (e.key === "Enter") {
      navigate(input.trim() ? `${basePath}?q=${encodeURIComponent(input.trim())}` : basePath);
    }
  };

  const displayName = user?.display_name || user?.email || "Reader";
  const initials = displayName
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase())
    .join("");

  return (
    <header
      className="topbar-desktop"
      style={{
        position: "sticky",
        top: 0,
        zIndex: 40,
        height: 72,
        background: "var(--app-bar-bg)",
        backdropFilter: "blur(12px)",
        borderBottom: "1px solid var(--outline-variant)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 24px 0 288px",
        gap: 24,
      }}
    >
      {title && (
        <div style={{ fontSize: 12, textTransform: "uppercase", letterSpacing: 1, color: "var(--on-surface-variant)", marginTop: 8, whiteSpace: "nowrap" }}>
          {title}
        </div>
      )}

      <div style={{ flex: 1, maxWidth: 480, position: "relative" }}>
        <span className="icon" style={{ position: "absolute", left: 14, top: 20, color: "var(--on-surface-variant)", fontSize: 20 }}>
          search
        </span>
        <input
          type="text"
          value={input}
          onChange={onChange}
          onKeyDown={onKeyDown}
          placeholder="Search by title, author, genre, or date..."
          style={{
            width: "100%",
            padding: "12px 14px 12px 44px",
            border: "none",
            borderBottom: "2px solid var(--outline-variant)",
            borderRadius: "6px 6px 0 0",
            background: "var(--surface-container-low)",
            outline: "none",
            fontSize: 16,
            fontFamily: "var(--font-body)",
          }}
        />
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        {children}
        <UiModeToggle />
        <button className="btn-icon">
          <span className="icon" style={{ fontSize: 22 }}>notifications</span>
        </button>
        <div
          style={{
            width: 40,
            height: 40,
            borderRadius: "50%",
            background: "var(--secondary-container)",
            color: "var(--on-secondary-container)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontWeight: 600,
            border: "1px solid var(--outline-variant)",
          }}
        >
          {initials}
        </div>
      </div>
    </header>
  );
}
