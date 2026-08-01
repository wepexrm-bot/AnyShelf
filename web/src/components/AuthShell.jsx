import React from "react";
import { Link } from "react-router-dom";

export default function AuthShell({ title, subtitle, children, footer }) {
  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "40px 16px",
      }}
    >
      <div style={{ width: "100%", maxWidth: 420 }}>
        <div style={{ textAlign: "center", marginBottom: 32 }}>
          <div
            style={{
              width: 56,
              height: 56,
              borderRadius: 14,
              background: "var(--primary)",
              color: "var(--on-primary)",
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
              marginBottom: 16,
            }}
          >
            <span className="icon" style={{ fontSize: 30 }}>menu_book</span>
          </div>
          <h1 style={{ fontFamily: "var(--font-display)", fontSize: 28, color: "var(--primary)" }}>
            Anyshelf
          </h1>
          <p style={{ margin: "6px 0 0", color: "var(--on-surface-variant)", fontSize: 14 }}>
            Digital Library
          </p>
        </div>

        <div
          className="card"
          style={{ padding: "32px 28px", borderRadius: 12 }}
        >
          <h2 style={{ fontFamily: "var(--font-display)", fontSize: 24, marginBottom: 4 }}>
            {title}
          </h2>
          {subtitle && (
            <p style={{ margin: "0 0 24px", color: "var(--on-surface-variant)", fontSize: 14 }}>
              {subtitle}
            </p>
          )}
          {children}
        </div>

        {footer && (
          <p style={{ textAlign: "center", marginTop: 20, fontSize: 14, color: "var(--on-surface-variant)" }}>
            {footer}
          </p>
        )}

        <p style={{ textAlign: "center", marginTop: 12, fontSize: 13, color: "var(--outline)" }}>
          <Link to="/" style={{ color: "var(--primary)" }}>Back to library</Link>
        </p>
      </div>
    </div>
  );
}
