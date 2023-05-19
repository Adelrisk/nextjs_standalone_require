FROM node:18-alpine AS base

# 1. Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache dumb-init libc6-compat

WORKDIR /app

RUN corepack enable
# Install dependencies based on the preferred package manager
COPY .yarn ./.yarn/
COPY ./package.json ./
COPY package.json yarn.lock .yarnrc.yml ./

RUN yarn install

# 2. Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=deps /app/.yarn/ ./.yarn
COPY package.json yarn.lock .yarnrc.yml ./
COPY . ./
# This will do the trick, use the corresponding env file for each environment.
# COPY .env.production.sample .env.production
RUN yarn install
RUN yarn build

# 3. Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Use dumb-init to prevent node running as PID 1. See https://github.com/Yelp/dumb-init#why-you-need-an-init-system
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init

# Make sure we have the latest security updates
RUN apk --no-cache -U upgrade

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing

# COPY --chown=nextjs:nodejs ./fake_modules/ ./node_modules/
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone/server.js ./
COPY --from=builder --chown=nextjs:nodejs /app/public* ./public/
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone/.yarn/cache/*/node_modules* ./node_modules/
# COPY --from=builder --chown=nextjs:nodejs /app/frontends/esig-webapp/.next/standalone/frontends/esig-webapp/ ./
# COPY --from=builder --chown=nextjs:nodejs /app/frontends/esig-webapp/.next/standalone/.yarn/cache/*/node_modules* ./node_modules/
COPY --from=builder --chown=nextjs:nodejs /app/.next/static* ./.next/static

# WORKDIR /app/frontends/esig-webapp

USER nextjs

EXPOSE 3000

ENV PORT 3000

# CMD ["dumb-init", "yarn", "start:custom"]
CMD ["dumb-init", "yarn", "node", "server.js"]
