# Feature Specification: QOTD Nanoservice

**Feature Branch**: `001-qotd-nanoservice`
**Created**: 2025-12-01
**Status**: Draft
**Input**: User description: "quotez is a tiny Zig nanoservice implementing the Quote of the Day (RFC 865) protocol over TCP and UDP. It loads quotes from local directories, auto-detecting TXT, CSV, JSON, TOML, YAML, or fallback plaintext. Detection order: JSON → CSV → TOML → YAML → plaintext. Parsing must be tolerant, trimming whitespace, skipping empty lines, and normalizing UTF-8. All quotes are merged into a single in-memory list with global deduplication via hashing. Supported selection modes: random (default), sequential, random-no-repeat, shuffle-cycle. quotez must poll input directories for changes on a configurable interval (default 60s) and rebuild the quote store only when changes are detected. Configuration is provided via a simple top-level TOML file defining server host/port, quote directories, polling interval, and selection mode. No hot config reload in MVP. The service must run TCP and UDP servers concurrently on port 17 by default (configurable). TCP sends one quote per connection then closes; UDP replies once per datagram. Deployment: fully static Zig binary packaged in a scratch container containing only /quotez, /quotez.toml, and /data/quotes (mounted). Prefer non-root. Explicit non-goals (MVP): remote sources (FTP/SFTP/SMB/WebDAV/HTTP), REST API, dashboards, metrics, authentication, templating, and hot config reload."

## Clarifications

### Session 2025-12-01

- Q: When the quote store is empty (no quotes loaded or all filtered out), how should the service respond to QOTD requests? → A: Continue running but send empty response and log warning
- Q: What level of logging should the service provide for operational visibility? → A: Startup/shutdown, config load, quote store builds, errors only (minimal but sufficient)
- Q: In "shuffle-cycle" mode, when should the quote list be reshuffled? → A: Reshuffle immediately when the last quote in current shuffle is served, AND reshuffle whenever the quote store is rebuilt (new/modified quotes detected)
- Q: How strictly should malformed configuration be treated? → A: Exit on required fields missing or invalid types; use defaults for optional fields with warnings
- Q: In "sequential" mode, when the quote store is rebuilt (files changed), should the service continue from its current position or reset to position 0? → A: Reset to position 0 (start of new list)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Serve Quotes Over TCP (Priority: P1)

A system administrator deploys quotez to provide inspirational quotes to terminal users on a local network. Users connect via telnet or netcat to receive a single quote, which the service delivers according to RFC 865 and closes the connection immediately.

**Why this priority**: TCP is the primary protocol for QOTD (RFC 865) and represents the core value proposition. Without this, the service cannot fulfill its fundamental purpose.

**Independent Test**: Can be fully tested by starting the service, connecting via `telnet localhost 17` or `nc localhost 17`, receiving a single quote, and verifying the connection closes automatically. Delivers immediate value as a functioning QOTD server.

**Acceptance Scenarios**:

1. **Given** quotez is running with default configuration, **When** a client connects to TCP port 17, **Then** the service sends exactly one quote and closes the connection
2. **Given** the quote store contains 100 quotes, **When** multiple clients connect sequentially, **Then** each receives a quote according to the configured selection mode (random by default)
3. **Given** quotez is running with TCP enabled, **When** a client connects and receives a quote, **Then** the quote text is properly UTF-8 encoded with normalized whitespace
4. **Given** quotez is configured to listen on a custom TCP port, **When** a client connects to that port, **Then** the service responds with a quote
5. **Given** the service has no quotes loaded, **When** a client connects via TCP, **Then** the connection closes immediately without sending any data

---

### User Story 2 - Serve Quotes Over UDP (Priority: P2)

A network monitoring system sends UDP datagrams to quotez to retrieve quotes for display dashboards. The service responds with a single quote datagram without maintaining connection state.

**Why this priority**: UDP support is required by RFC 865 for stateless quote delivery. It enables integration with monitoring tools and low-overhead clients, but TCP is sufficient for basic operation.

**Independent Test**: Can be tested by sending a UDP datagram to port 17 using `echo "" | nc -u localhost 17` and receiving a single quote response. Works independently of TCP implementation.

**Acceptance Scenarios**:

1. **Given** quotez is running with default configuration, **When** a client sends a UDP datagram to port 17, **Then** the service responds with exactly one quote datagram
2. **Given** the quote store contains quotes, **When** multiple UDP requests arrive, **Then** each receives a quote according to the configured selection mode
3. **Given** quotez is configured to listen on a custom UDP port, **When** a client sends a datagram to that port, **Then** the service responds with a quote
4. **Given** the service has no quotes loaded, **When** a UDP datagram arrives, **Then** the service sends no response (silent drop)

---

### User Story 3 - Load Quotes from Local Files (Priority: P1)

An administrator places quote files in various formats (TXT, CSV, JSON, TOML, YAML) into the configured directory. The service automatically detects each file's format, parses all quotes, deduplicates them, and makes them available for serving.

**Why this priority**: Without quote loading, the service has nothing to serve. This is foundational infrastructure that P1 and P2 depend on. Although listed as P1, it's actually a prerequisite for all other stories.

**Independent Test**: Can be tested by placing quote files in the data directory, starting the service, and verifying via logs or by requesting quotes that all formats are parsed correctly and duplicates are removed. Delivers value by proving the quote store works.

**Acceptance Scenarios**:

1. **Given** a directory contains files with .txt, .csv, .json, .toml, and .yaml extensions, **When** quotez starts, **Then** all files are scanned and quotes are extracted using format auto-detection in the order JSON → CSV → TOML → YAML → plaintext
2. **Given** quote files contain leading/trailing whitespace, empty lines, and various UTF-8 characters, **When** quotes are loaded, **Then** whitespace is trimmed, empty lines are skipped, and UTF-8 is normalized
3. **Given** multiple files contain identical quotes, **When** the quote store is built, **Then** duplicates are removed via content hashing and only unique quotes remain
4. **Given** a quote file contains malformed entries (e.g., invalid JSON, broken CSV rows), **When** parsing occurs, **Then** the service skips malformed entries and continues loading valid quotes without crashing
5. **Given** the configured directory is empty or contains no valid quotes, **When** quotez starts, **Then** the service starts successfully with an empty quote store and logs a warning

---

### User Story 4 - Reload Quotes on File Changes (Priority: P3)

An administrator adds new quote files or modifies existing ones while quotez is running. The service detects these changes during its polling cycle and automatically rebuilds the quote store without requiring a restart.

**Why this priority**: Hot reloading improves operational convenience but isn't critical for MVP. Administrators can restart the service to pick up new quotes if needed.

**Independent Test**: Can be tested by starting the service, adding/modifying quote files, waiting for the polling interval, and verifying new quotes appear in responses without restarting the service.

**Acceptance Scenarios**:

1. **Given** quotez is running with a polling interval of 60 seconds, **When** the polling cycle executes, **Then** the service checks configured directories for file modifications (timestamp or hash changes)
2. **Given** a quote file has been added or modified since the last poll, **When** the change is detected, **Then** the quote store is rebuilt with the new/updated quotes
3. **Given** no files have changed since the last poll, **When** the polling cycle executes, **Then** the quote store is NOT rebuilt to avoid unnecessary processing
4. **Given** quotez is configured with a custom polling interval, **When** the service runs, **Then** polling occurs at the specified interval (e.g., 30 seconds, 120 seconds)
5. **Given** quote reloading is in progress, **When** clients connect, **Then** the service continues to serve quotes from the current store without interruption

---

### User Story 5 - Quote Selection Modes (Priority: P2)

An administrator configures quotez to serve quotes in different patterns: random (default), sequential, random-no-repeat, or shuffle-cycle. This allows tailored behavior for different use cases (e.g., sequential for testing, random-no-repeat for variety).

**Why this priority**: Selection modes enhance usability and testing but aren't essential for basic operation. Random mode (default) is sufficient for most users.

**Independent Test**: Can be tested by configuring each mode, requesting multiple quotes, and verifying the selection behavior matches expectations (e.g., sequential returns quotes in order, random-no-repeat doesn't repeat until all quotes served).

**Acceptance Scenarios**:

1. **Given** quotez is configured with `mode = "random"`, **When** clients request quotes, **Then** each quote is selected randomly from the entire store (may repeat)
2. **Given** quotez is configured with `mode = "sequential"`, **When** clients request quotes, **Then** quotes are returned in order from first to last, then wrap to the beginning
3. **Given** quotez is configured with `mode = "random-no-repeat"`, **When** clients request quotes, **Then** each quote is selected randomly without repeating until all quotes have been served, then the cycle restarts
4. **Given** quotez is configured with `mode = "shuffle-cycle"`, **When** clients request quotes, **Then** the quote list is shuffled once, quotes are served in shuffled order, the list is reshuffled when the last quote is served, and the list is also reshuffled whenever the quote store is rebuilt
5. **Given** the selection mode is changed in the configuration file, **When** the service is restarted, **Then** the new mode takes effect immediately

---

### User Story 6 - Configuration via TOML File (Priority: P1)

An administrator creates a quotez.toml configuration file specifying server host, TCP/UDP ports, quote directories, polling interval, and selection mode. The service reads this configuration on startup and operates according to the specified parameters.

**Why this priority**: Configuration is foundational—without it, the service cannot be customized for different environments. This is a prerequisite for deployment flexibility.

**Independent Test**: Can be tested by creating various configuration files, starting the service, and verifying it behaves according to each configuration (listens on correct ports, loads from correct directories, uses correct selection mode).

**Acceptance Scenarios**:

1. **Given** a quotez.toml file specifies TCP and UDP ports, **When** quotez starts, **Then** the service binds to the specified ports
2. **Given** the configuration specifies one or more quote directories, **When** quotez starts, **Then** all specified directories are scanned for quote files
3. **Given** the configuration specifies a polling interval, **When** quotez runs, **Then** the service polls for file changes at the specified interval
4. **Given** the configuration specifies a selection mode, **When** quotes are served, **Then** the service uses the specified mode
5. **Given** the configuration file is missing or required fields (quote directories) are invalid, **When** quotez starts, **Then** the service exits with a clear error message indicating the configuration problem
6. **Given** the configuration file has missing or invalid optional fields (ports, polling interval, selection mode), **When** quotez starts, **Then** the service uses documented default values and logs a warning for each defaulted field
7. **Given** the configuration is changed while the service is running, **When** the polling cycle executes, **Then** the service continues using the original configuration (no hot reload in MVP)

---

### Edge Cases

- What happens when a quote file is deleted during runtime? (Service should handle gracefully during next reload, removing quotes from that file)
- What happens when a quote file exceeds reasonable size limits? (Service should load quotes successfully unless system memory is exhausted; no artificial limits in MVP)
- What happens when a quote contains only whitespace or special characters? (Whitespace-only quotes are skipped; special characters are preserved if valid UTF-8)
- What happens when the same quote appears in multiple files? (Deduplication removes all but one instance)
- What happens when TCP and UDP ports conflict or are already in use? (Service should exit with an error message on startup)
- What happens when multiple clients connect simultaneously? (Service handles concurrent connections according to the underlying transport's capabilities)
- What happens when a client disconnects before receiving the full quote? (TCP handles partial sends; UDP is fire-and-forget)
- What happens when the quote directory doesn't exist? (Service should exit with an error message indicating the missing directory)
- What happens in sequential mode when the quote store is rebuilt during serving? (Service resets to position 0 in the new quote list)
- What happens when no selection mode is specified in config? (Service defaults to "random" mode)

## Requirements *(mandatory)*

### Functional Requirements

**Protocol Compliance**

- **FR-001**: Service MUST implement RFC 865 Quote of the Day protocol over both TCP and UDP
- **FR-002**: TCP connections MUST receive exactly one quote and then close immediately
- **FR-003**: UDP requests MUST receive exactly one quote datagram in response
- **FR-004**: Service MUST listen on port 17 by default for both TCP and UDP (configurable)
- **FR-005**: Service MUST run TCP and UDP servers concurrently

**Quote Loading**

- **FR-006**: Service MUST load quotes from local directories only (no remote sources)
- **FR-007**: Service MUST support TXT, CSV, JSON, TOML, and YAML file formats
- **FR-008**: Service MUST auto-detect file formats in this order: JSON → CSV → TOML → YAML → plaintext
- **FR-009**: Service MUST parse quotes with error tolerance (skip malformed entries, continue processing)
- **FR-010**: Service MUST trim leading/trailing whitespace from quotes
- **FR-011**: Service MUST skip empty lines during parsing
- **FR-012**: Service MUST normalize quote text to valid UTF-8 encoding

**Quote Store**

- **FR-013**: Service MUST merge all parsed quotes into a single in-memory list
- **FR-014**: Service MUST deduplicate quotes globally via content hashing
- **FR-015**: Service MUST support four selection modes: random (default), sequential, random-no-repeat, shuffle-cycle
- **FR-016**: Service MUST serve quotes according to the configured selection mode with these specific behaviors:
  - **random**: Select any quote randomly on each request (may repeat immediately)
  - **sequential**: Serve quotes in list order, wrapping to position 0 after the last quote; reset to position 0 when quote store is rebuilt
  - **random-no-repeat**: Select randomly without repeating until all quotes served, then reset exhausted set and continue; reset exhausted set when quote store is rebuilt
  - **shuffle-cycle**: Shuffle list on startup/reload, serve in shuffled order, reshuffle when last quote served or when quote store rebuilt
- **FR-017**: Service MUST continue running when quote store is empty, sending empty responses to TCP (close immediately) and UDP (no response), and logging a warning on startup and each reload that results in zero quotes

**Reloading**

- **FR-018**: Service MUST poll configured directories for file changes at a configurable interval (default 60 seconds)
- **FR-019**: Service MUST rebuild the quote store only when file changes are detected (modification time or content hash)
- **FR-020**: Service MUST NOT interrupt active connections during quote store reloading

**Configuration**

- **FR-021**: Service MUST read configuration from a TOML file on startup
- **FR-022**: Configuration MUST define quote directories (required field - service exits if missing or invalid)
- **FR-023**: Configuration MAY define TCP port (optional, default 17), UDP port (optional, default 17), host address (optional, default 0.0.0.0)
- **FR-024**: Configuration MAY define polling interval (optional, default 60 seconds) and selection mode (optional, default "random")
- **FR-025**: Service MUST exit with a clear error message if required configuration fields are missing or have invalid types
- **FR-026**: Service MUST use documented default values for optional configuration fields that are missing or invalid, logging a warning for each defaulted field
- **FR-027**: Service MUST validate configuration field types (ports as integers 1-65535, directories as strings/arrays, polling interval as positive integer, mode as valid string enum)
- **FR-028**: Service MUST NOT support hot configuration reload in MVP (requires restart)

**Deployment**

- **FR-029**: Service MUST compile to a fully static binary with zero runtime dependencies
- **FR-030**: Container image MUST use scratch base image
- **FR-031**: Container MUST contain only: /quotez binary, /quotez.toml config, and /data/quotes mount point
- **FR-032**: Service SHOULD run as a non-root user when deployed

**Observability**

- **FR-033**: Service MUST log to stdout with minimal structured information: startup/shutdown events, configuration loaded, quote store builds (file count, quote count, duplicates removed), file parsing errors, empty quote store warnings, fatal errors
- **FR-034**: Service MUST NOT log individual QOTD requests (no per-request logging)

**Explicit Non-Goals (MVP)**

- **FR-035**: Service MUST NOT support remote quote sources (FTP, SFTP, SMB, WebDAV, HTTP)
- **FR-036**: Service MUST NOT provide REST API endpoints
- **FR-037**: Service MUST NOT include web dashboards or UIs
- **FR-038**: Service MUST NOT include metrics/observability frameworks (Prometheus, StatsD, etc.)
- **FR-039**: Service MUST NOT include authentication or authorization
- **FR-040**: Service MUST NOT support quote templating or advanced formatting
- **FR-041**: Service MUST NOT support hot configuration reload

### Key Entities

- **Quote**: A text string loaded from a file, normalized, deduplicated, and served in response to QOTD requests. Attributes: content (UTF-8 string), hash (for deduplication), source file (optional, for debugging).

- **Quote Store**: An in-memory collection of all loaded quotes with selection state. Attributes: quote list, current selection mode, current position (for sequential/shuffle modes), exhausted set (for random-no-repeat mode).

- **Configuration**: Settings loaded from quotez.toml on startup. Attributes: TCP port, UDP port, host address, quote directories list, polling interval, selection mode.

- **File Watcher**: Polling mechanism that checks configured directories for changes. Attributes: last scan timestamp, file modification times/hashes, polling interval.

### Assumptions

- **File System**: Service assumes POSIX-compliant file system with standard timestamp metadata.
- **Quote File Size**: No artificial size limits; assumes quote files fit in available system memory.
- **Quote Length**: Assumes individual quotes are reasonable length (< 512 bytes typical); no hard limit enforced in MVP.
- **Concurrency**: Assumes the underlying OS and network stack handle TCP concurrency; service doesn't impose artificial connection limits.
- **Character Encoding**: Input files are assumed to be UTF-8 or ASCII-compatible; non-UTF-8 encodings are normalized or may result in replacement characters.
- **Error Handling**: Invalid configuration or missing directories are fatal errors (service exits); malformed quote files are non-fatal (service skips bad entries and continues).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Service successfully responds to QOTD requests over TCP within 10ms of connection establishment (measured from server's perspective)
- **SC-002**: Service successfully responds to QOTD requests over UDP within 10ms of datagram receipt
- **SC-003**: Service handles at least 100 concurrent TCP connections without refusing connections or crashing
- **SC-004**: Service parses and loads 10,000 quotes from mixed file formats (JSON, CSV, TOML, YAML, TXT) in under 5 seconds on startup
- **SC-005**: Service correctly deduplicates quotes, resulting in zero duplicates served even when source files contain identical quotes
- **SC-006**: Service detects file changes and reloads quote store within one polling interval (default 60 seconds) plus processing time
- **SC-007**: Service continues serving quotes without interruption during quote store reloading
- **SC-008**: Service runs continuously for 24 hours under normal load (10 requests/minute) without memory leaks or crashes
- **SC-009**: Static binary size is under 5MB (measured after compilation)
- **SC-010**: Container image size is under 10MB (measured after building scratch-based image)
- **SC-011**: Administrator can deploy and configure service in under 5 minutes using provided quotez.toml and container image
- **SC-012**: Service startup time is under 2 seconds for a dataset of 1,000 quotes across 20 files
