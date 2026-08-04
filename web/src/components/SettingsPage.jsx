import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import Sidebar from "./Sidebar";
import { api } from "../api";
import { useAuth } from "../auth";
import AppHeader from "./AppHeader";
import PasswordInput from "./PasswordInput";
import { useUiMode } from "../uiMode";

export default function SettingsPage() {
  const { user, logout } = useAuth();
  const [mode, changeMode] = useUiMode();
  const navigate = useNavigate();
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  const handleChangePassword = async (e) => {
    e.preventDefault();
    setError(null);
    setMessage(null);
    if (newPassword.length < 8) {
      setError("New password must be at least 8 characters.");
      return;
    }
    if (newPassword !== confirm) {
      setError("New passwords do not match.");
      return;
    }
    setLoading(true);
    try {
      await api("/auth/change-password", {
        method: "POST",
        body: { old_password: oldPassword, new_password: newPassword },
      });
      setMessage("Password changed successfully.");
      setOldPassword("");
      setNewPassword("");
      setConfirm("");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ minHeight: "100vh" }}>
      <Sidebar />
      <AppHeader title="Settings" />
      <main className="main-desktop" style={{ paddingTop: 48, paddingBottom: 64, paddingRight: 24 }}>
        <div style={{ maxWidth: 640, margin: "0 auto" }}>
          <h2 style={{ fontFamily: "var(--font-display)", fontSize: 32, marginBottom: 8 }}>Settings</h2>
      <p className="text-muted" style={{ margin: "0 0 32px" }}>
        Manage your account and reading preferences.
      </p>

      <div className="card" style={{ padding: 24, marginBottom: 24 }}>
        <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, marginBottom: 4 }}>Appearance</h3>
        <p className="text-muted" style={{ margin: "0 0 16px", fontSize: 14 }}>
          Choose between light and dark mode for the app interface.
        </p>
        <div
          style={{
            display: "flex",
            background: "var(--surface-container-low)",
            borderRadius: 8,
            padding: 4,
            border: "1px solid var(--outline-variant)",
            maxWidth: 280,
          }}
        >
          {[
            { id: "light", label: "Light", icon: "light_mode" },
            { id: "dark", label: "Dark", icon: "dark_mode" },
          ].map((m) => (
            <button
              key={m.id}
              onClick={() => changeMode(m.id)}
              style={{
                flex: 1,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: 8,
                padding: "8px 16px",
                borderRadius: 6,
                border: "none",
                background: mode === m.id ? "var(--surface-container-high)" : "transparent",
                color: mode === m.id ? "var(--on-surface)" : "var(--on-surface-variant)",
                fontWeight: 500,
              }}
            >
              <span className="icon" style={{ fontSize: 18 }}>{m.icon}</span>
              {m.label}
            </button>
          ))}
        </div>
      </div>

      <div className="card" style={{ padding: 24, marginBottom: 24 }}>
        <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, marginBottom: 16 }}>Account</h3>
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div className="field">
            <label>Email</label>
            <input value={user?.email || ""} readOnly />
          </div>
          <div className="field">
            <label>Display name</label>
            <input value={user?.display_name || ""} readOnly />
          </div>
          {user && !user.is_verified && (
            <p className="text-muted" style={{ fontSize: 13, margin: 0 }}>
              Your email is not verified yet.
            </p>
          )}
        </div>
      </div>

      <div className="card" style={{ padding: 24 }}>
        <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, marginBottom: 4 }}>Change password</h3>
        <p className="text-muted" style={{ margin: "0 0 20px", fontSize: 14 }}>
          Use a strong password you don't use elsewhere.
        </p>

        {message && <div className="alert alert-success">{message}</div>}
        {error && <div className="alert alert-error">{error}</div>}

        <form onSubmit={handleChangePassword} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="field">
            <label htmlFor="old">Current password</label>
            <PasswordInput
              id="old"
              required
              value={oldPassword}
              onChange={(e) => setOldPassword(e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="new">New password</label>
            <PasswordInput
              id="new"
              required
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="confirm">Confirm new password</label>
            <PasswordInput
              id="confirm"
              required
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </div>
          <div style={{ display: "flex", gap: 12 }}>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? "Saving..." : "Change password"}
            </button>
            <button
              type="button"
              className="btn btn-ghost"
              onClick={() => {
                logout();
                navigate("/login");
              }}
            >
              Sign out
            </button>
          </div>
        </form>
        </div>
        </div>
      </main>
    </div>
  );
}
