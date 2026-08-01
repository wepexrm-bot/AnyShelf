import React, { useState } from "react";
import { Link } from "react-router-dom";
import AuthShell from "./AuthShell";
import { api } from "../api";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await api("/auth/forgot-password", { method: "POST", body: { email }, auth: false });
      setSent(true);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthShell
      title="Reset your password"
      subtitle="Enter your email and we'll send you a link to set a new password."
      footer={
        <>
          Remembered it? <Link to="/login" style={{ color: "var(--primary)" }}>Log in</Link>
        </>
      }
    >
      {error && <div className="alert alert-error">{error}</div>}
      {sent ? (
        <div className="alert alert-success">
          If an account exists for <strong>{email}</strong>, a password reset link is on its way. The
          link expires in 30 minutes.
        </div>
      ) : (
        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
            />
          </div>
          <button type="submit" className="btn btn-primary btn-block" disabled={loading}>
            {loading ? "Sending..." : "Send reset link"}
          </button>
        </form>
      )}
    </AuthShell>
  );
}
