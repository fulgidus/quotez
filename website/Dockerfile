# quotez website - Multi-stage Bun build
#
# Build:
#   docker build -f website/Dockerfile -t quotez-web:latest website/
#
# Run:
#   docker run -d -p 3000:3000 \
#     -e QOTD_API_HOST=qotd-service \
#     -e QOTD_API_PORT=8080 \
#     -e QOTD_TCP_HOST=qotd-service \
#     -e QOTD_TCP_PORT=17 \
#     -v quotez-web-data:/data \
#     quotez-web:latest

# ==============================================================================
# Stage 1: Builder - Bun with build tools
# ==============================================================================
FROM oven/bun:1 AS builder

WORKDIR /build

# Copy package files
COPY package.json package.json
COPY package-lock.json* package-lock.json*

# Install all dependencies (including dev for Vite build)
RUN bun install

# Copy source files
COPY src/ src/
COPY public/ public/
COPY index.html index.html
COPY tsconfig.json tsconfig.json
COPY vite.config.ts vite.config.ts

# Build Vite SPA
RUN bun run build

# ==============================================================================
# Stage 2: Runtime - Minimal Bun image
# ==============================================================================
FROM oven/bun:1

# OCI labels
LABEL org.opencontainers.image.title="quotez-web"
LABEL org.opencontainers.image.description="quotez website server - React SPA with Bun"
LABEL org.opencontainers.image.version="0.1.0"
LABEL org.opencontainers.image.source="https://github.com/fulgidus/quotez"

WORKDIR /app

# Set environment variables with defaults
ENV PORT=3000 \
    QOTD_API_HOST=qotd-service \
    QOTD_API_PORT=8080 \
    QOTD_TCP_HOST=qotd-service \
    QOTD_TCP_PORT=17 \
    QOTD_API_USERNAME=admin \
    QOTD_API_PASSWORD=quotez \
    DB_PATH=/data/settings.db

# Create data directory for SQLite database
RUN mkdir -p /data

# Copy package.json for production install
COPY package.json package.json

# Install production dependencies only
RUN bun install --production

# Copy server runtime files
COPY server.ts server.ts

# Copy library files needed at runtime
COPY src/lib/ src/lib/

# Copy database schema
COPY db/ db/

# Copy built SPA from builder stage
COPY --from=builder /build/dist/ dist/

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s CMD bun run -e "const res = await fetch('http://localhost:3000/'); process.exit(res.ok ? 0 : 1)" || exit 1

# Run server
CMD ["bun", "run", "server.ts"]
