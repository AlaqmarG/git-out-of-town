import { Pool } from "pg";

const globalForDb = globalThis as unknown as { pool?: Pool };

function createPool(): Pool {
  const p = new Pool({ connectionString: process.env.DATABASE_URL, max: 10 });
  // An idle client dropped by Postgres emits 'error' on the pool, and an
  // unhandled 'error' on an EventEmitter takes the process down with it. A
  // database blip must cost us a query, not the whole site. Attached here
  // rather than to the export so a hot reload doesn't stack up listeners.
  p.on("error", (err) => console.error("[db] idle client error", err));
  return p;
}

export const pool = globalForDb.pool ?? createPool();

if (process.env.NODE_ENV !== "production") globalForDb.pool = pool;

export const UPLOAD_DIR = process.env.UPLOAD_DIR ?? "/data/uploads";
