import React, { useEffect, useState } from "react";
import Sidebar from "./Sidebar";
import { api } from "../api";
import { useAuth } from "../auth";
import AppHeader from "./AppHeader";

function StatCard({ value, label }) {
  return (
    <div
      className="card"
      style={{
        padding: 20,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        textAlign: "center",
      }}
    >
      <div style={{ fontFamily: "var(--font-display)", fontSize: 36, color: "var(--primary)", lineHeight: 1 }}>
        {value}
      </div>
      <div style={{ fontSize: 12, textTransform: "uppercase", letterSpacing: 1, color: "var(--on-surface-variant)", marginTop: 8 }}>
        {label}
      </div>
    </div>
  );
}

export default function ProfilePage() {
  const { user } = useAuth();
  const [stats, setStats] = useState(null);
  const [monthly, setMonthly] = useState([]);
  const [activity, setActivity] = useState([]);
  const [shelves, setShelves] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const [s, m, a, sh] = await Promise.all([
        api("/stats/").catch(() => null),
        api("/stats/monthly").catch(() => []),
        api("/social/activity").catch(() => []),
        api("/shelves/shared/all").catch(() => []),
      ]);
      setStats(s);
      setMonthly(m);
      setActivity(a);
      setShelves(sh);
      setLoading(false);
    })();
  }, []);

  if (loading) return <div className="loading">Loading profile…</div>;

  const displayName = user?.display_name || "Reader";
  const initials = displayName
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase())
    .join("");
  const maxMinutes = Math.max(1, ...monthly.map((m) => m.minutes));

  const timeAgo = (iso) => {
    const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (s < 60) return "just now";
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    return `${Math.floor(s / 86400)}d ago`;
  };

  return (
    <div style={{ minHeight: "100vh" }}>
      <Sidebar />

      <AppHeader title="Reading Dashboard" />

      <main className="main-desktop" style={{ paddingTop: 32, paddingBottom: 64, paddingRight: 24 }}>
        <div style={{ width: "100%", display: "grid", gridTemplateColumns: "minmax(0, 2fr) minmax(280px, 1fr)", gap: 24 }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 32 }}>
            {/* Profile header */}
            <div
              className="card"
              style={{
                padding: 32,
                display: "flex",
                alignItems: "center",
                gap: 24,
                background: "var(--surface-container-low)",
                position: "relative",
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  width: 96,
                  height: 96,
                  borderRadius: "50%",
                  background: "var(--secondary-container)",
                  color: "var(--on-secondary-container)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 36,
                  fontWeight: 700,
                  border: "4px solid var(--surface-container-highest)",
                  flexShrink: 0,
                }}
              >
                {initials}
              </div>
              <div>
                <h2 style={{ fontFamily: "var(--font-display)", fontSize: 28, marginBottom: 8 }}>{displayName}</h2>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 8 }}>
                  {user?.is_verified && <span className="badge badge-primary">Verified reader</span>}
                  <span className="badge badge-secondary">
                    {stats?.current_streak ?? 0} day streak
                  </span>
                </div>
              </div>
            </div>

            {/* Stats bento */}
            <section>
              <h3
                style={{
                  fontFamily: "var(--font-display)",
                  fontSize: 20,
                  marginBottom: 16,
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                }}
              >
                <span className="icon text-primary" style={{ fontSize: 20 }}>monitoring</span>
                Reading Dashboard
              </h3>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(170px, 1fr))", gap: 16 }}>
                <StatCard value={stats?.books_completed ?? 0} label="Books Read" />
                <StatCard value={stats?.total_pages ?? 0} label="Pages" />
                <StatCard value={`${Math.round((stats?.total_reading_minutes ?? 0) / 60)}h`} label="Hours" />
                <StatCard value={stats?.best_streak ?? 0} label="Best Streak" />
              </div>

              {/* Monthly bar chart */}
              <div className="card" style={{ padding: 20, marginTop: 16 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                  <span style={{ fontSize: 12, textTransform: "uppercase", letterSpacing: 1, color: "var(--on-surface-variant)" }}>
                    Reading minutes — last 6 months
                  </span>
                  <span className="icon text-muted" style={{ fontSize: 20 }}>trending_up</span>
                </div>
                <div style={{ display: "flex", alignItems: "flex-end", gap: 12, height: 96 }}>
                  {monthly.map((m) => (
                    <div key={m.month} style={{ flex: 1, textAlign: "center" }}>
                      <div
                        style={{
                          height: `${Math.max(4, (m.minutes / maxMinutes) * 100)}%`,
                          background: "var(--primary)",
                          borderRadius: "4px 4px 0 0",
                          minHeight: 4,
                          opacity: m.minutes === 0 ? 0.25 : 1,
                        }}
                      />
                      <div style={{ fontSize: 11, color: "var(--on-surface-variant)", marginTop: 6 }}>{m.label}</div>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            {/* Shared shelves */}
            <section>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
                <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, display: "flex", alignItems: "center", gap: 8 }}>
                  <span className="icon text-primary" style={{ fontSize: 20 }}>auto_awesome_mosaic</span>
                  Shared Shelves
                </h3>
              </div>
              {shelves.length === 0 ? (
                <div className="card" style={{ padding: 24, color: "var(--on-surface-variant)" }}>
                  No public shelves from other readers yet.
                </div>
              ) : (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(300px, 1fr))", gap: 16 }}>
                  {shelves.map((shelf) => (
                    <div key={shelf.id} className="card" style={{ overflow: "hidden" }}>
                      <div
                        style={{
                          height: 96,
                          background: "var(--surface-container-high)",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          gap: 0,
                        }}
                      >
                        <div style={{ width: 44, height: 64, background: "var(--surface)", boxShadow: "0 2px 6px rgba(0,0,0,0.12)", borderRadius: 4, transform: "rotate(-6deg)" }} />
                        <div style={{ width: 44, height: 64, background: "var(--surface)", boxShadow: "0 2px 6px rgba(0,0,0,0.12)", borderRadius: 4, zIndex: 2 }} />
                        <div style={{ width: 44, height: 64, background: "var(--surface)", boxShadow: "0 2px 6px rgba(0,0,0,0.12)", borderRadius: 4, transform: "rotate(6deg)" }} />
                      </div>
                      <div style={{ padding: 16 }}>
                        <h4 style={{ fontFamily: "var(--font-ui)", fontSize: 15, fontWeight: 600, marginBottom: 4 }}>
                          {shelf.name}
                        </h4>
                        <p className="text-muted" style={{ fontSize: 13, margin: "0 0 12px" }}>
                          {shelf.book_count} items · by {shelf.owner_display_name || "Reader"}
                        </p>
                        <button
                          className="btn btn-ghost btn-block"
                          onClick={() => api(`/shelves/${shelf.id}/follow`, { method: "POST" })}
                        >
                          <span className="icon" style={{ fontSize: 16 }}>bookmark_add</span>
                          {shelf.followed ? "Following" : "Follow Shelf"}
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>

          {/* Activity feed */}
          <div>
            <div style={{ position: "sticky", top: 96 }}>
              <h3
                style={{
                  fontFamily: "var(--font-display)",
                  fontSize: 20,
                  marginBottom: 16,
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  paddingBottom: 12,
                  borderBottom: "1px solid var(--outline-variant)",
                }}
              >
                <span className="icon text-primary" style={{ fontSize: 20 }}>forum</span>
                Reader Network
              </h3>
              {activity.length === 0 ? (
                <div className="card" style={{ padding: 20, color: "var(--on-surface-variant)" }}>
                  No activity yet. Finish a book or follow other readers to see updates here.
                </div>
              ) : (
                <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                  {activity.slice(0, 12).map((a) => (
                    <div key={a.id} style={{ display: "flex", gap: 12 }}>
                      <div
                        style={{
                          width: 40,
                          height: 40,
                          borderRadius: "50%",
                          background: "var(--surface-container-high)",
                          color: "var(--on-surface-variant)",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          flexShrink: 0,
                          fontWeight: 600,
                        }}
                      >
                        {(a.author?.display_name || "R").slice(0, 1).toUpperCase()}
                      </div>
                      <div style={{ flex: 1 }}>
                        <p style={{ margin: 0, fontSize: 14 }}>
                          <strong>{a.author?.display_name}</strong>{" "}
                          {a.kind === "finished" && (
                            <>finished <em>{a.book?.title}</em></>
                          )}
                          {a.kind === "highlighted" && (
                            <>highlighted a passage in <em>{a.book?.title}</em></>
                          )}
                          {a.kind === "shelf_shared" && (
                            <>shared the shelf <em>{a.shelf?.name}</em></>
                          )}
                          {a.kind === "reviewed" && <>{a.text}</>}
                        </p>
                        {a.text && a.kind !== "reviewed" && (
                          <p
                            className="card"
                            style={{ padding: 10, fontSize: 13, fontStyle: "italic", margin: "8px 0 0", background: "var(--surface)" }}
                          >
                            "{a.text}"
                          </p>
                        )}
                        <span style={{ fontSize: 11, color: "var(--outline)", display: "block", marginTop: 4 }}>
                          {timeAgo(a.created_at)}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}
