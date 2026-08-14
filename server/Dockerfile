FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
# `npm install`, not `npm ci`, deliberately. sharp pulls platform-specific
# optional dependencies (@img/sharp-*, @emnapi/*), and npm resolves those into
# the lockfile for whichever platform last ran an install (npm/cli#4828). A
# lockfile generated on Windows fails `npm ci` on this ARM64 Alpine image, and
# one regenerated here fails `npm ci` back on Windows — there is no single
# lockfile that satisfies both. `npm install` still honours the lockfile
# wherever it is consistent and re-resolves only the divergent optional deps.
# This Docker build is the only npm ci consumer in the repo, so nothing else
# depends on the stricter behaviour.
RUN npm install --no-audit --no-fund
COPY tsconfig*.json nest-cli.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
# The `node` user ships with the official image (uid 1000). The server fetches
# cover art from arbitrary third-party URLs and parses untrusted protobuf out of
# uploaded backups, so it has no business doing that as root. /data/storage is
# chowned here so the volume mount is writable without any host-side setup.
RUN mkdir -p /data/storage && chown -R node:node /data/storage /app
USER node
ENV STORAGE_DIR=/data/storage
EXPOSE 3000
# Liveness for the orchestrator: `restart: always` cannot help a process that is
# up but wedged, and Docker has no other way to tell the two apart.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/v1/health || exit 1
# Migrations run automatically on boot (migrationsRun: true).
CMD ["node", "dist/main"]
