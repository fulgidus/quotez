# quotez QOTD nanoservice - Multi-stage multi-arch Docker build
#
# Build single-arch:
#   docker build -t quotez:latest .
#
# Build multi-arch:
#   docker buildx build --platform linux/amd64,linux/arm64 -t quotez:latest .
#
# Run:
#   docker run -d -p 8017:8017/tcp -p 8017:8017/udp -p 8080:8080/tcp \
#     -v ./quotes:/data/quotes:ro \
#     quotez:latest

# ==============================================================================
# Stage 1: Builder - Alpine + Zig 0.16.0-dev.2682+02142a54d
# ==============================================================================
FROM alpine:latest AS builder

# Install dependencies for Zig download and build
RUN apk add --no-cache curl tar xz

# Install Zig 0.16.0-dev.2682+02142a54d (latest 0.16 build per AGENTS.md)
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) ZIG_ARCH="x86_64" ;; \
      arm64) ZIG_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    curl -fsSL "https://ziglang.org/builds/zig-${ZIG_ARCH}-linux-0.16.0-dev.2682+02142a54d.tar.xz" -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv zig-${ZIG_ARCH}-linux-0.16.0-dev.2682+02142a54d /opt/zig && \
    rm zig.tar.xz

ENV PATH="/opt/zig:${PATH}"

# Set working directory
WORKDIR /build

# Copy source files
COPY src/ src/
COPY build.zig build.zig

# Build static binary with Zig native cross-compilation
# CRITICAL: Use zig build-exe workaround (zig build produces corrupted binaries per notepad)
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) ZIG_TARGET="x86_64-linux-musl" ;; \
      arm64) ZIG_TARGET="aarch64-linux-musl" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    zig build-exe src/main.zig \
      -lc \
      -Doptimize=ReleaseSmall \
      -Dtarget=${ZIG_TARGET} \
      --name quotez && \
    strip quotez

# ==============================================================================
# Stage 2: Runtime - Distroless static with nonroot user
# ==============================================================================
FROM gcr.io/distroless/static:nonroot

# OCI labels
LABEL org.opencontainers.image.title="quotez"
LABEL org.opencontainers.image.description="RFC 865 Quote of the Day (QOTD) nanoservice in Zig"
LABEL org.opencontainers.image.version="0.1.0"
LABEL org.opencontainers.image.source="https://github.com/fulgidus/quotez"
LABEL org.opencontainers.image.created="2026-03-03T00:00:00Z"

# Copy binary from builder
COPY --from=builder /build/quotez /quotez

# Copy production configuration
COPY quotez.docker.toml /quotez.toml

# Expose ports
EXPOSE 8017/tcp
EXPOSE 8017/udp
EXPOSE 8080/tcp

# Run as nonroot (UID 65532) - inherited from distroless/static:nonroot
USER 65532

# Entrypoint with config path argument
ENTRYPOINT ["/quotez", "/quotez.toml"]
