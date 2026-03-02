# quotez QOTD nanoservice - Minimal scratch container
# 
# Build the binary first with:
#   zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
#
# Then build the image:
#   docker build -t quotez .
#
# Run with:
#   docker run -d -p 17:17/tcp -p 17:17/udp \
#     -v ./quotes:/data/quotes:ro \
#     quotez

FROM scratch

# Copy static binary (must be pre-built with musl)
COPY zig-out/bin/quotez /quotez

# Copy default configuration (Docker-specific with /data/quotes path)
COPY quotez.docker.toml /quotez.toml

# Create sample quotes directory (override with volume mount)
COPY tests/fixtures/quotes/ /data/quotes/

# RFC 865 standard QOTD port
EXPOSE 17/tcp 17/udp

# Health check not available in scratch, use external orchestrator health checks

# Run the service
ENTRYPOINT ["/quotez"]
