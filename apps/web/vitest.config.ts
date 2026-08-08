import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    // Mirrors the `@/*` alias from tsconfig.json.
    alias: { "@": path.resolve(__dirname, ".") },
  },
  test: {
    include: ["lib/**/*.test.ts", "app/**/*.test.ts"],
    environment: "node",
  },
});
