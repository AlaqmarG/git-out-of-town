import { Client } from "pg";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Server-Sent Events feed for live updates.
 *
 * Listens on Postgres `new_piece` (fired by the `pieces_notify` trigger) and
 * streams each event as `event: piece` + `data: <json>`. Both clients consume
 * this: the web map for live drop-ins, and iOS to show pieces in real time.
 *
 * Uses a DEDICATED `pg.Client`, never the shared pool — pooled connections get
 * recycled and silently stop listening (see apps/web/CLAUDE.md).
 */
export async function GET() {
  const encoder = new TextEncoder();
  let cleanup: () => void = () => {};

  const stream = new ReadableStream({
    async start(controller) {
      const send = (event: string, data: unknown) => {
        controller.enqueue(encoder.encode(`event: ${event}\n`));
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
      };

      const heartbeat = setInterval(() => {
        controller.enqueue(encoder.encode(`: ping\n\n`));
      }, 15_000);

      const client = new Client({ connectionString: process.env.DATABASE_URL });
      cleanup = () => {
        clearInterval(heartbeat);
        client.removeAllListeners("notification");
        client.end().catch(() => {});
      };

      try {
        await client.connect();
        await client.query("LISTEN new_piece");
        client.on("notification", (msg) => {
          if (!msg.payload) return;
          try {
            send("piece", JSON.parse(msg.payload));
          } catch {
            // Ignore malformed payloads; keep the stream alive.
          }
        });
      } catch (err) {
        console.error("[stream] db connection failed", err);
        send("error", { message: "stream unavailable" });
      }
    },
    cancel() {
      cleanup();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
