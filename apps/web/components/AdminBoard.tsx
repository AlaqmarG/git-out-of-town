"use client";

import { uploadUrl } from "@got/shared";
import { useCallback, useEffect, useState } from "react";
import { palette } from "@/lib/theme";

interface Row {
  id: number;
  lat: number;
  lng: number;
  art: string;
  scene: string | null;
  city: string | null;
  createdAt: string;
  deleted: boolean;
}

const KEY = "got.admin.secret";

/**
 * Moderation for public UGC. Designed to be usable one-handed on a phone while
 * standing in a room, because that is when it will actually be needed.
 *
 * Removals are soft and reversible — the likeliest use of this screen is a
 * panicked tap during judging, and an unrecoverable delete would be worse than
 * the thing being removed.
 */
export default function AdminBoard() {
  const [secret, setSecret] = useState(() =>
    typeof window === "undefined" ? "" : (localStorage.getItem(KEY) ?? ""),
  );
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<number | null>(null);

  const load = useCallback(async (s: string) => {
    if (!s) return;
    try {
      // The fetch starts before any setState, so calling this from an effect
      // cannot trigger a synchronous cascading render.
      const res = await fetch("/api/admin/pieces", { headers: { "x-admin-secret": s } });
      setError(null);
      if (res.status === 401) {
        setError("That key was not accepted.");
        setRows(null);
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const body = (await res.json()) as { pieces: Row[] };
      setRows(body.pieces);
      localStorage.setItem(KEY, s);
    } catch {
      setError("Could not reach the server.");
    }
  }, []);

  // Only on mount: retyping the key should not refetch on every keystroke.
  // Deferred a tick so no state update happens synchronously inside the effect.
  useEffect(() => {
    const saved = typeof window === "undefined" ? "" : (localStorage.getItem(KEY) ?? "");
    if (!saved) return;
    const id = setTimeout(() => void load(saved), 0);
    return () => clearTimeout(id);
  }, [load]);

  const act = async (id: number, deleted: boolean) => {
    setBusy(id);
    try {
      await fetch("/api/admin/pieces", {
        method: deleted ? "POST" : "DELETE",
        headers: { "Content-Type": "application/json", "x-admin-secret": secret },
        body: JSON.stringify({ id }),
      });
      // Optimistic: the operator needs instant feedback, not a round trip.
      setRows((prev) => prev?.map((r) => (r.id === id ? { ...r, deleted: !deleted } : r)) ?? null);
    } finally {
      setBusy(null);
    }
  };

  return (
    <main className="min-h-dvh px-4 py-6" style={{ background: palette.ink }}>
      <div className="mx-auto max-w-3xl">
        <h1 className="text-xl font-semibold" style={{ color: palette.text }}>
          Moderation
        </h1>
        <p className="mt-1 text-xs" style={{ color: palette.textMuted }}>
          Removals are reversible. Hidden pieces disappear from the map and every count.
        </p>

        <div className="mt-4 flex gap-2">
          <input
            type="password"
            value={secret}
            onChange={(e) => setSecret(e.target.value)}
            placeholder="Admin key"
            autoComplete="off"
            className="flex-1 rounded-xl px-3 py-2.5 text-sm"
            style={{ background: palette.raised, color: palette.text, border: `1px solid ${palette.line}` }}
          />
          <button
            type="button"
            onClick={() => void load(secret)}
            className="rounded-xl px-4 py-2.5 text-sm font-medium"
            style={{ background: palette.accent, color: "#fff" }}
          >
            Load
          </button>
        </div>

        {error && (
          <p className="mt-3 text-sm" style={{ color: palette.accent }}>
            {error}
          </p>
        )}

        {rows && (
          <>
            <p className="mt-5 text-xs" style={{ color: palette.textMuted }}>
              {rows.filter((r) => !r.deleted).length} visible · {rows.filter((r) => r.deleted).length} hidden
            </p>

            <ul className="mt-3 grid grid-cols-2 gap-3 pb-10 sm:grid-cols-3">
              {rows.map((r) => (
                <li
                  key={r.id}
                  className="overflow-hidden rounded-xl"
                  style={{
                    background: palette.raised,
                    border: `1px solid ${r.deleted ? palette.accentDim : palette.line}`,
                    opacity: r.deleted ? 0.5 : 1,
                  }}
                >
                  <div className="relative" style={{ aspectRatio: "4 / 3", background: palette.ink }}>
                    {r.scene && (
                      /* eslint-disable-next-line @next/next/no-img-element */
                      <img src={uploadUrl(r.scene)} alt="" className="absolute inset-0 h-full w-full object-cover" />
                    )}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={uploadUrl(r.art)} alt="" className="absolute inset-0 m-auto" style={{ width: "62%" }} />
                  </div>
                  <div className="p-2">
                    <p className="truncate text-[11px]" style={{ color: palette.textMuted }}>
                      #{r.id} · {r.city ?? "unknown"}
                    </p>
                    <button
                      type="button"
                      disabled={busy === r.id}
                      onClick={() => void act(r.id, r.deleted)}
                      className="mt-1.5 w-full rounded-lg py-2 text-xs font-medium"
                      style={{
                        background: r.deleted ? palette.raised : palette.accentDim,
                        color: palette.text,
                        border: `1px solid ${palette.line}`,
                      }}
                    >
                      {busy === r.id ? "…" : r.deleted ? "Restore" : "Hide"}
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </main>
  );
}
