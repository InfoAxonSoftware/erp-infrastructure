# ── Stage 1: Build ─────────────────────────────────────────────────────────────
# The React app source lives in the ./app/ subdirectory of the build context.
# deploy.sh clones / pulls your external React repo into docker/react/app/
# before building so this Dockerfile always finds the source at ./app/.
FROM node:20-alpine AS builder

WORKDIR /build

# Install dependencies first (separate layer for better cache reuse)
COPY app/package*.json ./
RUN npm ci --silent

# Copy the rest of the source and build
COPY app/ .
RUN npm run build

# ── Stage 2: Production ────────────────────────────────────────────────────────
FROM nginx:1.25-alpine AS production

RUN apk add --no-cache curl

# Copy built SPA assets from the builder stage
COPY --from=builder /build/dist /usr/share/nginx/html

# Copy SPA-aware nginx config (served from the infra repo, not the React repo)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost/health || exit 1
