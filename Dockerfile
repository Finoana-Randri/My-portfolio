ARG PROXY
FROM ${PROXY}node:22-alpine AS base

ARG RELEASE
ENV NEXT_PUBLIC_RELEASE=$RELEASE
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

RUN apk update \
    && apk add --no-cache \
    ca-certificates \
    gosu \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# ------------------------------------------------------------
# DEPS
# ------------------------------------------------------------
FROM base AS deps

RUN apk add --no-cache libc6-compat ca-certificates

# Correct Corepack activation
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy only lockfiles → best caching
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile --prod false \
    && pnpm store prune \
    && rm -rf ~/.pnpm-store

# ------------------------------------------------------------
# BUILDER
# ------------------------------------------------------------
FROM base AS builder

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY --from=deps /app/node_modules ./node_modules

COPY next.config.mjs tsconfig.json ./
COPY eslint.config.mjs ./
COPY postcss.config.mjs ./
COPY sentry.server.config.ts sentry.edge.config.ts ./
COPY next-sitemap.config.cjs ./
COPY locales ./locales

COPY src ./src
COPY public ./public
COPY package.json pnpm-lock.yaml ./

RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm lint \
    && pnpm build \
    && pnpm prune --prod

# ------------------------------------------------------------
# RUNNER
# ------------------------------------------------------------
FROM base AS runner

RUN corepack enable && corepack prepare pnpm@latest --activate

RUN addgroup -g 1001 nodejs && \
    adduser -D -u 1001 -G nodejs nextjs

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/public ./public
COPY --from=builder /app/locales ./locales
COPY --from=builder /app/next.config.mjs ./next.config.mjs
COPY --from=builder /app/next-sitemap.config.cjs ./next-sitemap.config.cjs
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/tsconfig.json ./tsconfig.json
COPY --from=builder /app/src ./src
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next

EXPOSE 3000
CMD ["./node_modules/.bin/next", "start"]