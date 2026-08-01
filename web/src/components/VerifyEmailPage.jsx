import React, { useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import AuthShell from "./AuthShell";
import { useAuth } from "../auth";

export default function VerifyEmailPage() {
  const { verifyEmail, resendVerification } = useAuth();
  const [searchParams] = useSearchParams();
  const [email, setEmail] = useState(searchParams.get("email") || "");
  const [code, setCode] = useState("");
  const [status, setStatus] = useState("entry");
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  const handleVerify = async (e) => {
    e.preventDefault();
    setError(null);
    setMessage(null);
    setLoading(true);
    try {
      const res = await verifyEmail(email, code.trim());
      setStatus("verified");
      setMessage(res.status === "already_verified" ? "This email is already verified." : "Your email has been verified.");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleResend = async () => {
    setError(null);
    setMessage(null);
    setLoading(true);
    try {
      await resendVerification(email);
      setMessage("A new verification code has been sent to your email.");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthShell
      title="Verify your email"
      subtitle="We sent a 6-digit code to your email. Enter it below to finish signing up."
      footer={
        status === "verified" ? (
          <Link to="/login" style={{ color: "var(--primary)" }}>Go to log in</Link>
        ) : (
          <Link to="/login" style={{ color: "var(--primary)" }}>Back to log in</Link>
        )
      }
    >
      {error && <div className="alert alert-error">{error}</div>}
      {message && <div className="alert alert-success">{message}</div>}

      {status === "verified" ? (
        <div className="alert alert-success">
          Your email has been verified. You can now log in to your account.
        </div>
      ) : (
        <form onSubmit={handleVerify} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="field">
            <label htmlFor="vemail">Email</label>
            <input
              id="vemail"
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
            />
          </div>
          <div className="field">
            <label htmlFor="vcode">Verification code</label>
            <input
              id="vcode"
              type="text"
              required
              inputMode="numeric"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              placeholder="6-digit code"
              style={{ textAlign: "center", fontSize: 20, letterSpacing: 8, fontWeight: 600 }}
            />
          </div>
          <button type="submit" className="btn btn-primary btn-block" disabled={loading || code.length !== 6}>
            {loading ? "Verifying..." : "Verify email"}
          </button>
          <button type="button" className="btn btn-ghost btn-block" onClick={handleResend} disabled={loading}>
            Resend code
          </button>
        </form>
      )}
    </AuthShell>
  );
}
