<!--
Sync Impact Report
==================
Version Change: Initial → 1.0.0
Type: MINOR (initial constitution ratification)

Modified Principles: N/A (initial version)
Added Sections:
  - Core Principles (7 principles defined)
  - MVP Scope Boundaries
  - Governance

Removed Sections: N/A

Templates Consistency Check:
  ✅ plan-template.md - Constitution Check section present, aligns with principles
  ✅ spec-template.md - Requirements structure supports protocol/config/deployment constraints
  ✅ tasks-template.md - Phase organization supports foundational/user story model

Follow-up TODOs:
  - None (all placeholders filled)

Rationale:
  This is the initial ratification of the quotez constitution based on the MVP
  specification provided. Version 1.0.0 marks the first complete, authoritative
  governance document for the project. All seven core principles are clearly defined
  with explicit technical constraints and non-negotiable requirements.
-->

# quotez Constitution

## Core Principles

### I. Protocol Compliance

The service MUST implement RFC 865 Quote of the Day protocol correctly over both TCP and UDP transports. Each request receives exactly one quote; TCP connections close after sending, UDP sends a single datagram response. No protocol extensions, modifications, or deviations are permitted in the MVP.

**Rationale**: Protocol compliance ensures interoperability with standard QOTD clients and maintains simplicity. Strict adherence prevents scope creep and maintains the "nano" service philosophy.

### II. Local Quote Loading

Quotes MUST be loaded exclusively from local directories specified in configuration. The service MUST support TXT, CSV, JSON, TOML, and YAML formats with automatic format detection in this order: JSON → CSV → TOML → YAML → plaintext. Parsing MUST be error-tolerant (skip malformed entries), normalize whitespace, enforce UTF-8 encoding, and skip empty lines.

**Rationale**: Local-only loading keeps the service self-contained and eliminates network dependencies, failure modes, and security attack surfaces. Format auto-detection and tolerant parsing maximize usability without requiring users to pre-process quote files.

### III. Quote Store

All parsed quotes MUST be merged into a single in-memory list with global deduplication via content hashing. The service MUST support four quote selection modes: `random`, `sequential`, `random-no-repeat`, and `shuffle-cycle`. The active mode is set via configuration.

**Rationale**: Deduplication prevents redundant quotes across multiple source files. Multiple selection modes provide flexibility for different use cases (testing with sequential, variety with random, etc.) without adding complexity to the core engine.

### IV. Reloading

The service MUST poll configured input directories on a configurable interval (default: 60 seconds). Quote store rebuild occurs only when file changes are detected (modification time or content hash). Reloading MUST NOT interrupt active connections.

**Rationale**: Polling enables quote updates without service restart. Change detection avoids unnecessary re-parsing. Non-disruptive reloading maintains service availability.

### V. Configuration

All service parameters (TCP/UDP ports, quote directories, polling interval, selection mode) MUST be defined in a single TOML configuration file. The MVP does NOT support hot configuration reload—changes require service restart.

**Rationale**: TOML provides human-readable configuration with strong typing. Deferring hot reload to post-MVP reduces complexity and potential race conditions during development.

### VI. Deployment

The service MUST compile to a fully static Zig binary with zero runtime dependencies. The Docker image MUST use `scratch` base containing only: the `quotez` binary, `quotez.toml` config, and a `/data/quotes` mount point for quote files. The service SHOULD run as a non-root user in production.

**Rationale**: Static binary eliminates dependency hell and simplifies deployment. Scratch containers minimize attack surface and image size. Non-root execution follows security best practices.

### VII. Non-Goals (MVP)

The MVP explicitly excludes: remote quote sources (FTP/SFTP/SMB/WebDAV/HTTP), REST APIs, web dashboards, metrics/observability frameworks, authentication/authorization, quote templating, and advanced formatting. These may be considered for post-MVP releases if justified.

**Rationale**: Strict scope boundaries prevent feature creep and maintain focus on core QOTD protocol delivery. Each excluded feature adds complexity, dependencies, and potential failure modes that contradict the "nano" service goal.

## MVP Scope Boundaries

- **In Scope**: RFC 865 protocol, local file parsing (5 formats), deduplication, 4 selection modes, periodic polling, TOML config, static Zig binary, scratch container
- **Out of Scope**: Remote sources, HTTP APIs, web UIs, authentication, metrics, templating, hot config reload
- **Post-MVP Candidates** (requires justification): Prometheus metrics, structured logging, Syslog integration, hot reload

## Governance

This constitution is the authoritative source of technical and architectural requirements for quotez. All code, documentation, and design decisions MUST comply with these principles.

### Amendment Process

1. Proposed amendments MUST be documented with rationale and impact analysis
2. Version number MUST be incremented following semantic versioning:
   - **MAJOR**: Principle removal, redefinition, or backward-incompatible scope change
   - **MINOR**: New principle added or material expansion of existing principle
   - **PATCH**: Clarifications, wording improvements, typo fixes
3. Amended constitution MUST include updated `Last Amended` date and sync impact report
4. All dependent templates and documentation MUST be updated for consistency

### Compliance Review

- All feature specifications MUST pass a "Constitution Check" gate before research begins
- Any complexity or scope addition outside these principles requires explicit justification
- Code reviews MUST verify adherence to protocol compliance, deployment, and non-goals constraints

**Version**: 1.0.0 | **Ratified**: 2025-12-01 | **Last Amended**: 2025-12-01
