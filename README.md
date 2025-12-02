# quotez

A tiny Zig nanoservice implementing the Quote of the Day (RFC 865) protocol over TCP and UDP. It loads, normalizes, and deduplicates quotes from local files (txt/csv/json/toml/yaml) and serves them on demand. Ships as a static binary in a minimal scratch container.

## Features

- **RFC 865 Compliant**: Full TCP and UDP QOTD protocol support
- **Multi-Format Support**: Automatically parses TXT, CSV, JSON, TOML, and YAML files
- **Deduplication**: Blake3-based content hashing eliminates duplicate quotes
- **Selection Modes**: Random, sequential, random-no-repeat, and shuffle-cycle
- **Hot Reload**: Polls directories for changes and reloads without restart
- **Minimal Footprint**: Static binary < 5MB, Docker image < 10MB
- **Zero Dependencies**: Pure Zig standard library implementation

## Quick Start

### Prerequisites

- Zig 0.13.0 or later
- Docker (optional, for container deployment)

### Build

```bash
# Development build
zig build

# Release build (static, optimized for size)
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl

# Run tests
zig build test
```

### Configuration

Create a `quotez.toml` file:

```toml
[server]
host = "0.0.0.0"
tcp_port = 17
udp_port = 17

[quotes]
directories = ["/data/quotes"]
mode = "random"  # random | sequential | random-no-repeat | shuffle-cycle

[polling]
interval_seconds = 60
```

### Run

```bash
# Run locally (requires quotez.toml in current directory)
./zig-out/bin/quotez

# Test with netcat
nc localhost 17              # TCP
echo "" | nc -u localhost 17 # UDP
```

### Docker

```bash
# Build static binary
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl

# Build Docker image
docker build -t quotez:latest .

# Run container
docker run -d \
  -p 17:17/tcp -p 17:17/udp \
  -v $(pwd)/quotes:/data/quotes:ro \
  -v $(pwd)/quotez.toml:/quotez.toml:ro \
  quotez:latest
```

## Project Structure

```
src/
├── main.zig              # Entry point and event loop
├── config.zig            # TOML configuration parsing
├── logger.zig            # Structured logging
├── quote_store.zig       # In-memory quote storage
├── selector.zig          # Selection mode algorithms
├── parsers/
│   ├── parser.zig        # Format detection and dispatch
│   ├── txt.zig           # Plaintext parser
│   ├── csv.zig           # CSV parser
│   ├── json.zig          # JSON parser
│   ├── toml.zig          # TOML parser
│   └── yaml.zig          # YAML parser
└── servers/
    ├── tcp.zig           # TCP QOTD server
    └── udp.zig           # UDP QOTD server

tests/
├── integration/
│   └── protocol_test.zig # RFC 865 compliance tests
└── fixtures/
    └── quotes/           # Sample quote files for testing
```

## Development Status

**Phase Progress**: 36/74 tasks complete (48.6%)

- ✅ **Phase 1 (Setup)**: Complete
- ✅ **Phase 2 (Foundational)**: Complete - Config, Logger, QuoteStore, Selector
- ✅ **Phase 3 (US3 - Quote Loading)**: Complete - All 5 parsers implemented
- ✅ **Phase 4 (US6 - Configuration)**: Complete - TOML config with validation
- ✅ **Phase 5 (US1 - TCP Server)**: Complete - RFC 865 TCP implementation
- ✅ **Phase 6 (US2 - UDP Server)**: Complete - RFC 865 UDP implementation
- 🚧 **Phase 7 (US5 - Selection Modes)**: Pending - Edge case tests
- 🚧 **Phase 8 (US4 - Hot Reload)**: Pending - File watcher implementation
- 🚧 **Phase 9 (Polish)**: In Progress - Binary optimization, deployment

See [specs/001-qotd-nanoservice/tasks.md](specs/001-qotd-nanoservice/tasks.md) for detailed task breakdown.

## Documentation

- **[Specification](specs/001-qotd-nanoservice/spec.md)**: Feature requirements and user stories
- **[Implementation Plan](specs/001-qotd-nanoservice/plan.md)**: Architecture and tech stack
- **[Data Model](specs/001-qotd-nanoservice/data-model.md)**: Entity definitions and state machines
- **[Quickstart Guide](specs/001-qotd-nanoservice/quickstart.md)**: Deployment scenarios and examples
- **[Contracts](specs/001-qotd-nanoservice/contracts/)**: Protocol specs and config schema

## Contributing

This project follows the [.specify](/.specify/) development workflow. See [AGENTS.md](/AGENTS.md) for development guidelines.

## License

MIT
