import React, { createContext, useContext, useEffect, useState, useCallback } from "react";
import { api, getStoredUser, getToken, setToken, setStoredUser } from "./api";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(getStoredUser());
  const [initializing, setInitializing] = useState(true);

  const refreshUser = useCallback(async () => {
    if (!getToken()) {
      setUser(null);
      setInitializing(false);
      return null;
    }
    try {
      const me = await api("/auth/me");
      setUser(me);
      setStoredUser(me);
      return me;
    } catch {
      setToken(null);
      setStoredUser(null);
      setUser(null);
      return null;
    } finally {
      setInitializing(false);
    }
  }, []);

  useEffect(() => {
    refreshUser();
  }, [refreshUser]);

  const login = useCallback(
    async (email, password) => {
      const res = await api("/auth/login", {
        method: "POST",
        body: { email, password },
        auth: false,
      });
      setToken(res.access_token);
      setUser({ email: res.email, display_name: res.display_name, is_verified: res.is_verified });
      setStoredUser({ email: res.email, display_name: res.display_name, is_verified: res.is_verified });
      return res;
    },
    []
  );

  const register = useCallback(async (email, password, display_name) => {
    const res = await api("/auth/register", {
      method: "POST",
      body: { email, password, display_name },
      auth: false,
    });
    return res;
  }, []);

  const verifyEmail = useCallback(async (email, code) => {
    return api("/auth/verify-email", {
      method: "POST",
      body: { email, code },
      auth: false,
    });
  }, []);

  const resendVerification = useCallback(async (email) => {
    return api("/auth/resend-verification", {
      method: "POST",
      body: { email },
      auth: false,
    });
  }, []);

  const logout = useCallback(() => {
    setToken(null);
    setStoredUser(null);
    setUser(null);
  }, []);

  return (
    <AuthContext.Provider value={{ user, setUser, login, register, verifyEmail, resendVerification, logout, refreshUser, initializing }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
