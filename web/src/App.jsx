import React from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider, useAuth } from "./auth";
import Library from "./components/Library";
import BooksPage from "./components/BooksPage";
import ShelvesPage from "./components/ShelvesPage";
import Reader from "./components/Reader";
import ProfilePage from "./components/ProfilePage";
import SettingsPage from "./components/SettingsPage";
import LoginPage from "./components/LoginPage";
import SignupPage from "./components/SignupPage";
import ForgotPasswordPage from "./components/ForgotPasswordPage";
import ResetPasswordPage from "./components/ResetPasswordPage";
import VerifyEmailPage from "./components/VerifyEmailPage";
import { ShelfModalProvider } from "./components/ShelfModalContext";

function RequireAuth({ children }) {
  const { user, initializing } = useAuth();
  if (initializing) {
    return <div className="loading">Loading Anyshelf…</div>;
  }
  if (!user) {
    return <Navigate to="/login" replace />;
  }
  return children;
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <ShelfModalProvider>
          <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/forgot-password" element={<ForgotPasswordPage />} />
          <Route path="/reset-password" element={<ResetPasswordPage />} />
          <Route path="/verify-email" element={<VerifyEmailPage />} />
          <Route
            path="/"
            element={
              <RequireAuth>
                <Library />
              </RequireAuth>
            }
          />
          <Route
            path="/books"
            element={
              <RequireAuth>
                <BooksPage />
              </RequireAuth>
            }
          />
          <Route
            path="/shelves"
            element={
              <RequireAuth>
                <ShelvesPage />
              </RequireAuth>
            }
          />
          <Route
            path="/read/:bookId"
            element={
              <RequireAuth>
                <Reader />
              </RequireAuth>
            }
          />
          <Route
            path="/profile"
            element={
              <RequireAuth>
                <ProfilePage />
              </RequireAuth>
            }
          />
          <Route
            path="/settings"
            element={
              <RequireAuth>
                <SettingsPage />
              </RequireAuth>
            }
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        </ShelfModalProvider>
      </BrowserRouter>
    </AuthProvider>
  );
}
