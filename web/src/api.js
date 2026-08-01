const API_BASE = process.env.REACT_APP_API_BASE || "http://localhost:8000";

export function getToken() {
  return localStorage.getItem("cloudread_token");
}

export function setToken(token) {
  if (token) localStorage.setItem("cloudread_token", token);
  else localStorage.removeItem("cloudread_token");
}

export function getStoredUser() {
  try {
    return JSON.parse(localStorage.getItem("cloudread_user") || "null");
  } catch {
    return null;
  }
}

export function setStoredUser(user) {
  if (user) localStorage.setItem("cloudread_user", JSON.stringify(user));
  else localStorage.removeItem("cloudread_user");
}

export async function api(path, { method = "GET", body, formData, auth = true } = {}) {
  const headers = {};
  if (body && !formData) headers["Content-Type"] = "application/json";
  const token = getToken();
  if (auth && token) headers["Authorization"] = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers,
    body: formData || (body ? JSON.stringify(body) : undefined),
  });

  let data = null;
  const text = await res.text();
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    const err = new Error(
      (data && data.detail) || `Request failed (${res.status})`
    );
    err.status = res.status;
    throw err;
  }
  return data;
}

export default API_BASE;
