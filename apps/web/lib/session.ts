const KEY = "got.session";

/**
 * A stable anonymous id for this browser, used to attribute views and (later)
 * contributions. No account, no cookie banner, no personal data.
 */
export function sessionId(): string {
  if (typeof window === "undefined") return "server";
  let id = localStorage.getItem(KEY);
  if (!id) {
    id = `web-${crypto.randomUUID()}`;
    localStorage.setItem(KEY, id);
  }
  return id;
}
