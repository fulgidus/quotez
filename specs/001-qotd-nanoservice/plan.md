# Implementation Plan: QOTD Nanoservice

**Branch**: `001-qotd-nanoservice` | **Date**: 2025-12-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-qotd-nanoservice/spec.md`

## Summary

quotez is a lightweight Zig nanoservice implementing RFC 865 Quote of the Day protocol over TCP and UDP. It loads quotes from local files in multiple formats (TXT/CSV/JSON/TOML/YAML), stores them in memory with deduplication, and serves them via four configurable selection modes (random, sequential, random-no-repeat, shuffle-cycle). The service polls directories for changes, runs as a fully static binary, and ships in a minimal scratch container.

**Technical Approach**: Single-threaded event loop using Zig's standard library for TCP/UDP servers, with copy-on-write pointer swapping for safe quote store reloading. File format detection via extension and content sniffing. Blake3 hashing for deduplication. TOML parsing for configuration. Zero external dependencies beyond Zig stdlib.

## Technical Context

**Language/Version**: Zig 0.13.0 (latest stable)
**Primary Dependencies**: 
  - Zig standard library (net, fs, crypto, json, fmt)
  - Embedded TOML parser (zig-toml or inline parser)
  - No external runtime dependencies
  
**Storage**: In-memory ArrayList for quote storage, no persistence layer

**Testing**: 
  - Zig's built-in test framework (`zig test`)
  - Integration tests using subprocess spawning for protocol verification
  - Protocol tests against netcat/telnet clients
  
**Target Platform**: Linux x86_64/aarch64 (primary), musl libc for static linking
**Project Type**: Single binary CLI service  
**Performance Goals**: 
  - < 10ms response latency (TCP/UDP)
  - 100+ concurrent TCP connections
  - < 5s startup for 10k quotes
  - < 5MB binary size
  - < 10MB container image
  
**Constraints**: 
  - Zero runtime dependencies (static binary)
  - No hot configuration reload
  - No metrics/observability frameworks
  - Single-threaded architecture (simplified concurrency)
  
**Scale/Scope**: 
  - 1-10k quotes typical
  - 10-100 requests/minute expected load
  - Single instance deployment (no clustering/HA in MVP)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Protocol Compliance ✅
- **Requirement**: Implement RFC 865 over TCP and UDP, one quote per connection
- **Status**: PASS - Design includes TCP/UDP servers with single-quote-and-close semantics
- **Evidence**: User stories 1-2 verify protocol behavior; no extensions planned

### Local Quote Loading ✅
- **Requirement**: Support 5 file formats with auto-detection order JSON→CSV→TOML→YAML→plaintext
- **Status**: PASS - Parser module designed with format detection chain
- **Evidence**: FR-007, FR-008 specify formats and detection order

### Quote Store ✅
- **Requirement**: In-memory list with deduplication and 4 selection modes
- **Status**: PASS - QuoteStore module with Blake3 hashing and mode strategy pattern
- **Evidence**: FR-013 through FR-017 detail store requirements

### Reloading ✅
- **Requirement**: Poll directories every 60s (configurable), rebuild on changes, no interruption
- **Status**: PASS - Polling loop with copy-on-write pointer swap for atomic updates
- **Evidence**: FR-018 through FR-020 define polling behavior

### Configuration ✅
- **Requirement**: Single TOML file, no hot reload
- **Status**: PASS - Config loaded at startup, restart required for changes
- **Evidence**: FR-021 through FR-028 specify TOML config contract

### Deployment ✅
- **Requirement**: Static Zig binary, scratch container, non-root
- **Status**: PASS - Zig build with `-Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall` for static linking
- **Evidence**: FR-029 through FR-032 define deployment artifacts

### Non-Goals (MVP) ✅
- **Requirement**: No remote sources, APIs, dashboards, metrics, auth, templating
- **Status**: PASS - No components violate non-goals
- **Evidence**: FR-035 through FR-041 explicitly exclude these features

**Pre-Research Gate**: ✅ PASS - All constitution principles satisfied

---

**Post-Design Check** (2025-12-01 after Phase 1):

### Protocol Compliance ✅
- **Artifacts**: `contracts/qotd-protocol.md` documents RFC 865 compliance with TCP/UDP flows
- **Status**: PASS - Exact TCP close-after-send and UDP datagram behaviors defined
- **Evidence**: Protocol contract specifies compliance requirements table, wire formats, and test cases

### Local Quote Loading ✅
- **Artifacts**: `contracts/quote-formats.md` defines all 5 formats with parsing rules
- **Status**: PASS - Detection order JSON→CSV→TOML→YAML→plaintext explicitly documented
- **Evidence**: Format detection chain, parsing strategies, and error handling fully specified

### Quote Store ✅
- **Artifacts**: `data-model.md` QuoteStore entity with deduplication and selection modes
- **Status**: PASS - Blake3 hashing, 4 selection modes with state machines documented
- **Evidence**: QuoteStore state machine, Selector tagged union, deduplication flow diagrams

### Reloading ✅
- **Artifacts**: `data-model.md` FileWatcher entity, `data-model.md` rebuild flow
- **Status**: PASS - Polling with mtime comparison, atomic pointer swap for non-disruptive reload
- **Evidence**: FileWatcher state machine, rebuild trigger flow in data model

### Configuration ✅
- **Artifacts**: `contracts/config-schema.md` complete TOML specification
- **Status**: PASS - All fields, types, defaults, validation rules documented; no hot reload
- **Evidence**: Configuration lifecycle shows startup-only load, restart required for changes

### Deployment ✅
- **Artifacts**: `quickstart.md` Docker examples, build commands for static binary
- **Status**: PASS - Static musl builds, scratch container, non-root deployment documented
- **Evidence**: Quickstart shows `zig build -Dtarget=x86_64-linux-musl`, FROM scratch Dockerfile

### Non-Goals (MVP) ✅
- **Artifacts**: All design docs exclude remote sources, APIs, dashboards, metrics, auth
- **Status**: PASS - No violations introduced during design phase
- **Evidence**: Quickstart FAQ confirms MVP limitations, no post-MVP features included

**Post-Design Gate**: ✅ PASS - Design artifacts comply with all constitution principles. Ready for Phase 2 (tasks breakdown).

## Project Structure

### Documentation (this feature)

```text
specs/001-qotd-nanoservice/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output (dependency evaluation, Zig patterns)
├── data-model.md        # Phase 1 output (entities and state machines)
├── quickstart.md        # Phase 1 output (deployment and usage guide)
├── contracts/           # Phase 1 output (protocol specs and config schema)
│   ├── qotd-protocol.md # RFC 865 implementation details
│   ├── config-schema.md # TOML configuration reference
│   └── quote-formats.md # File format specifications
└── checklists/
    └── requirements.md  # Validation checklist
```

### Source Code (repository root)

```text
src/
├── main.zig                # Entry point, CLI argument parsing, initialization
├── config.zig              # TOML config loading and validation
├── quote_store.zig         # In-memory quote storage with deduplication
├── selector.zig            # Selection mode implementations (trait-based)
├── parsers/
│   ├── parser.zig          # Common parser interface
│   ├── txt.zig             # Plain text parser
│   ├── csv.zig             # CSV parser
│   ├── json.zig            # JSON parser
│   ├── toml.zig            # TOML parser
│   └── yaml.zig            # YAML parser
├── servers/
│   ├── tcp.zig             # TCP QOTD server
│   └── udp.zig             # UDP QOTD server
├── watcher.zig             # File system polling and change detection
└── logger.zig              # Minimal structured logging to stdout

tests/
├── unit/
│   ├── config_test.zig     # Config parsing and validation
│   ├── quote_store_test.zig # Deduplication and selection modes
│   ├── parsers_test.zig    # File format parsing
│   └── selector_test.zig   # Mode selection algorithms
├── integration/
│   ├── protocol_test.zig   # TCP/UDP RFC 865 compliance
│   ├── reload_test.zig     # Hot reloading behavior
│   └── end_to_end_test.zig # Full service lifecycle
└── fixtures/
    └── quotes/             # Sample quote files for testing
        ├── sample.txt
        ├── sample.csv
        ├── sample.json
        ├── sample.toml
        └── sample.yaml

build.zig                   # Zig build configuration
```

**Structure Decision**: Single project layout is appropriate for a nanoservice with < 3k LOC. All modules are library-style with a single `main.zig` entry point. Testing follows Zig's convention of co-locating test blocks within source files for unit tests, with separate `tests/` directory for integration tests. No need for frontend/backend split or mobile structure—this is a pure server daemon.

## Complexity Tracking

> No constitution violations detected. This section intentionally left empty.

