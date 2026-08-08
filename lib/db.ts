import { Pool } from "pg";

const globalForDb = globalThis as unknown as { pool?: Pool };

export const pool =
  globalForDb.pool ??
  new Pool({ connectionString: process.env.DATABASE_URL, max: 10 });

if (process.env.NODE_ENV !== "production") globalForDb.pool = pool;

export const UPLOAD_DIR = process.env.UPLOAD_DIR ?? "/data/uploads";
