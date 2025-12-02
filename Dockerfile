FROM scratch
COPY zig-out/bin/quotez /quotez
COPY quotez.toml /quotez.toml
ENTRYPOINT ["/quotez"]
