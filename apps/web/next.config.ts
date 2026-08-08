import path from "node:path";
import type { NextConfig } from "next";

/**
 * Dev-only: point `/api/*` and `/uploads/*` at a running deployment so the UI can
 * be developed against real data without a local Postgres.
 *
 *   DEV_PROXY_ORIGIN=https://gitoutoftown.129-153-49-190.sslip.io npm run dev
 *
 * Unset in production, so this is inert there.
 */
const proxyOrigin = process.env.DEV_PROXY_ORIGIN?.replace(/\/$/, "");

const nextConfig: NextConfig = {
  output: "standalone",
  // Monorepo: trace from the workspace root so the standalone bundle picks up
  // hoisted node_modules and the @got/shared package.
  outputFileTracingRoot: path.join(__dirname, "../../"),
  transpilePackages: ["@got/shared"],

  async rewrites() {
    if (!proxyOrigin) return [];
    // `beforeFiles` is required: our own /api routes exist on disk and would
    // otherwise win over the rewrite.
    return {
      beforeFiles: [
        { source: "/api/:path*", destination: `${proxyOrigin}/api/:path*` },
        { source: "/uploads/:path*", destination: `${proxyOrigin}/uploads/:path*` },
      ],
      afterFiles: [],
      fallback: [],
    };
  },
};

export default nextConfig;
