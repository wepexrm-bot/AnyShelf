import React from "react";
import { NavLink, useNavigate } from "react-router-dom";
import { useAuth } from "../auth";
import { useShelfModal } from "./ShelfModalContext";

const NAV_ITEMS = [
  { to: "/", label: "Home", icon: "home", end: true },
  { to: "/books", label: "Books", icon: "library_books" },
  { to: "/shelves", label: "Shelves", icon: "shelves" },
  { to: "/profile", label: "Stats", icon: "leaderboard" },
];

const FOOTER_ITEMS = [
  { to: "/settings", label: "Settings", icon: "settings" },
];

export default function Sidebar() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const { openCreateShelf } = useShelfModal();

  const handleLogout = () => {
    logout();
    navigate("/login");
  };

  const renderLink = ({ to, label, icon, end }) => (
    <NavLink key={to + label} to={to} end={end} className="sidebar-link">
      <span className="icon" style={{ fontSize: 20, flexShrink: 0 }}>{icon}</span>
      <span>{label}</span>
    </NavLink>
  );

  return (
    <nav
      style={{
        width: 256,
        flexDirection: "column",
        padding: 20,
        borderRight: "1px solid var(--outline-variant)",
        background: "var(--surface-container-low)",
        position: "fixed",
        top: 0,
        left: 0,
        bottom: 0,
        zIndex: 50,
      }}
      className="sidebar-desktop"
    >
      {/* Header */}
      <div style={{ padding: "8px 8px 24px", marginBottom: 24 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <img
            src={process.env.PUBLIC_URL + "/icons/icon-192.png"}
            alt="Anyshelf"
            style={{ width: 40, height: 40, borderRadius: 10, flexShrink: 0 }}
          />
          <div>
            <div style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 20, color: "var(--primary)", lineHeight: 1.1 }}>
              Anyshelf
            </div>
            <div style={{ fontSize: 12, color: "var(--on-surface-variant)" }}>Digital Library</div>
          </div>
        </div>
      </div>

      {/* CTA */}
      <div style={{ padding: "0 8px", marginBottom: 24 }}>
        <button
          className="btn btn-primary btn-block"
          onClick={openCreateShelf}
          style={{ padding: "12px 0", fontSize: 14, borderRadius: 9999 }}
        >
          <span className="icon" style={{ fontSize: 18 }}>add</span>
          New Shelf
        </button>
      </div>

      {/* Main nav */}
      <div style={{ display: "flex", flexDirection: "column", gap: 4, flex: 1 }}>
        {NAV_ITEMS.map(renderLink)}
      </div>

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", gap: 4, borderTop: "1px solid var(--outline-variant)", paddingTop: 16 }}>
        {FOOTER_ITEMS.map(renderLink)}
        <button onClick={handleLogout} className="sidebar-link">
          <span className="icon" style={{ fontSize: 20, flexShrink: 0 }}>logout</span>
          <span>Sign out</span>
        </button>
        {user && (
          <div style={{ padding: "12px 16px 0", fontSize: 13, color: "var(--on-surface-variant)" }}>
            <strong style={{ color: "var(--on-surface)" }}>{user.display_name || user.email}</strong>
            {!user.is_verified && (
              <div style={{ marginTop: 4 }}>
                <span className="badge badge-secondary">unverified</span>
              </div>
            )}
          </div>
        )}
      </div>
    </nav>
  );
}
