import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  output: "standalone",
  // Monorepo: trace from the workspace root so the standalone bundle picks up
  // hoisted node_modules and the @got/shared package.
  outputFileTracingRoot: path.join(__dirname, "../../"),
  transpilePackages: ["@got/shared"],
};

export default nextConfig;
