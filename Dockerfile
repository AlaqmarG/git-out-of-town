# syntax=docker/dockerfile:1
# Monorepo build. Context is the workspace root so npm can resolve @got/shared.

FROM node:22-alpine AS builder
WORKDIR /repo
# Manifests first — these change rarely, so npm ci stays cached across code edits.
COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/
COPY packages/shared/package.json packages/shared/
RUN npm ci
COPY . .
# NEXT_PUBLIC_* is inlined at build time, so it must be a build arg, not runtime env.
ARG NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=""
ENV NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=$NEXT_PUBLIC_GOOGLE_MAPS_API_KEY \
    NEXT_TELEMETRY_DISABLED=1
RUN npm run build -w @got/web

FROM node:22-alpine AS runner
WORKDIR /repo
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001 \
 && mkdir -p /data/uploads && chown -R nextjs:nodejs /data
# With outputFileTracingRoot at the workspace root, standalone mirrors the repo
# layout: server.js lands at apps/web/server.js with node_modules hoisted alongside.
COPY --from=builder --chown=nextjs:nodejs /repo/apps/web/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /repo/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder --chown=nextjs:nodejs /repo/apps/web/public ./apps/web/public
USER nextjs
EXPOSE 3000
CMD ["node", "apps/web/server.js"]
