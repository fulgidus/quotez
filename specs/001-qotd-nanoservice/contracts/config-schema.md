# Configuration Schema Contract

**Feature**: 001-qotd-nanoservice  
**Format**: TOML  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This document defines the complete configuration schema for quotez, including all fields, types, constraints, defaults, and validation rules. The configuration file (`quotez.toml`) is read once at startup and remains immutable for the service lifetime (no hot reload in MVP).

---

## Schema Definition

### TOML Structure

```toml
[server]
host = "0.0.0.0"       # Optional, default: "0.0.0.0"
tcp_port = 17          # Optional, default: 17
udp_port = 17          # Optional, default: 17

[quotes]
directories = [        # Required, no default
    "/data/quotes",
    "/etc/quotez/custom"
]
mode = "random"        # Optional, default: "random"

[polling]
interval_seconds = 60  # Optional, default: 60
```

---

## Field Reference

### `[server]` Section

Configuration for network binding and ports.

#### `server.host`

- **Type**: String
- **Required**: No
- **Default**: `"0.0.0.0"`
- **Constraints**:
  - MUST be a valid IPv4 address, IPv6 address, or hostname
  - Examples: `"0.0.0.0"`, `"127.0.0.1"`, `"::1"`, `"localhost"`
- **Description**: IP address or hostname to bind TCP and UDP sockets to
- **Behavior**:
  - `"0.0.0.0"` binds to all IPv4 interfaces
  - `"::"` binds to all IPv6 interfaces
  - `"127.0.0.1"` binds to loopback only (local access)

**Example**:
```toml
[server]
host = "0.0.0.0"  # Accept connections on all interfaces
```

**Validation**:
- If missing: Use default `"0.0.0.0"`, log INFO
- If invalid type (not string): Exit with error
- If invalid format (malformed IP): Exit with error during socket binding

---

#### `server.tcp_port`

- **Type**: Integer
- **Required**: No
- **Default**: `17`
- **Constraints**:
  - MUST be in range `[1, 65535]`
  - Standard QOTD port is 17 (requires root/CAP_NET_BIND_SERVICE on Linux)
- **Description**: TCP port for QOTD server to listen on
- **Behavior**:
  - Service binds to `host:tcp_port` on startup
  - Failure to bind (port in use, permissions) is fatal error

**Example**:
```toml
[server]
tcp_port = 8017  # Non-privileged port for testing
```

**Validation**:
- If missing: Use default `17`, log INFO
- If invalid type (not integer): Exit with error
- If out of range: Exit with error
- If port binding fails: Exit with error

---

#### `server.udp_port`

- **Type**: Integer
- **Required**: No
- **Default**: `17`
- **Constraints**:
  - MUST be in range `[1, 65535]`
  - MAY be the same as `tcp_port` (kernel allows dual binding)
- **Description**: UDP port for QOTD server to listen on
- **Behavior**:
  - Service binds to `host:udp_port` on startup
  - Failure to bind is fatal error

**Example**:
```toml
[server]
tcp_port = 17
udp_port = 17  # Same port for both protocols (standard QOTD)
```

**Validation**:
- If missing: Use default `17`, log INFO
- If invalid type (not integer): Exit with error
- If out of range: Exit with error
- If port binding fails: Exit with error

---

### `[quotes]` Section

Configuration for quote loading and selection behavior.

#### `quotes.directories`

- **Type**: Array of Strings
- **Required**: **YES** (fatal error if missing)
- **Default**: None (must be explicitly provided)
- **Constraints**:
  - MUST be non-empty array
  - Each element MUST be a valid file system path (absolute or relative)
  - Paths MAY contain `~` (home directory expansion implementation-defined)
- **Description**: List of directories to scan for quote files
- **Behavior**:
  - All directories are scanned recursively on startup and during reloads
  - Directories that don't exist at startup log WARNING but don't cause failure
  - Files in all directories are merged into single quote store with global deduplication

**Example**:
```toml
[quotes]
directories = [
    "/data/quotes",           # Absolute path
    "/etc/quotez/custom",     # Additional directory
    "./quotes"                # Relative path (relative to working directory)
]
```

**Validation**:
- If missing: Exit with error: `"Configuration error: 'quotes.directories' is required"`
- If not array: Exit with error
- If empty array: Exit with error
- If element is not string: Exit with error
- If directory doesn't exist at startup: Log WARNING, continue

---

#### `quotes.mode`

- **Type**: String (enum)
- **Required**: No
- **Default**: `"random"`
- **Constraints**:
  - MUST be one of: `"random"`, `"sequential"`, `"random-no-repeat"`, `"shuffle-cycle"`
  - Case-sensitive (lowercase only)
- **Description**: Quote selection algorithm
- **Behavior**:
  - `"random"`: Select any quote randomly on each request (may repeat immediately)
  - `"sequential"`: Serve quotes in list order, wrap to position 0 after last quote
  - `"random-no-repeat"`: Select randomly without repeating until all quotes served, then reset
  - `"shuffle-cycle"`: Shuffle list on startup/rebuild, serve in shuffled order, reshuffle on exhaustion

**Example**:
```toml
[quotes]
directories = ["/data/quotes"]
mode = "shuffle-cycle"  # No repeats until full cycle completes
```

**Validation**:
- If missing: Use default `"random"`, log INFO
- If invalid type (not string): Use default, log WARNING
- If invalid value (not in enum): Exit with error: `"Invalid selection mode: '<value>'. Must be one of: random, sequential, random-no-repeat, shuffle-cycle"`

---

### `[polling]` Section

Configuration for file system change detection.

#### `polling.interval_seconds`

- **Type**: Integer
- **Required**: No
- **Default**: `60`
- **Constraints**:
  - MUST be positive integer `>= 1`
  - Practical minimum: 1 second (too low may cause excessive I/O)
  - Recommended range: 10-300 seconds
- **Description**: How often to poll directories for file changes (in seconds)
- **Behavior**:
  - Service checks file modification times every `interval_seconds`
  - If changes detected, rebuild quote store
  - If no changes, skip rebuild

**Example**:
```toml
[polling]
interval_seconds = 120  # Check every 2 minutes
```

**Validation**:
- If missing: Use default `60`, log INFO
- If invalid type (not integer): Use default, log WARNING
- If `<= 0`: Exit with error: `"Polling interval must be positive"`

---

## Complete Example Configuration

```toml
# quotez.toml - Complete example configuration

[server]
# Bind to all interfaces (IPv4)
host = "0.0.0.0"

# Use standard QOTD port (requires root on Linux)
tcp_port = 17
udp_port = 17

[quotes]
# Required: List of directories to scan for quote files
directories = [
    "/data/quotes",           # Primary quote directory
    "/etc/quotez/custom",     # Additional quotes
    "/opt/quotes/community"   # Community-contributed quotes
]

# Optional: Quote selection algorithm
# Options: random (default), sequential, random-no-repeat, shuffle-cycle
mode = "shuffle-cycle"

[polling]
# Optional: How often to check for file changes (seconds)
# Default: 60 seconds
interval_seconds = 120
```

---

## Minimal Configuration

The minimal valid configuration requires only `quotes.directories`:

```toml
[quotes]
directories = ["/data/quotes"]
```

All other fields use defaults:
- `server.host` → `"0.0.0.0"`
- `server.tcp_port` → `17`
- `server.udp_port` → `17`
- `quotes.mode` → `"random"`
- `polling.interval_seconds` → `60`

---

## Validation Rules

### Startup Validation Sequence

1. **File Existence**: Check if `quotez.toml` exists
   - If missing: Exit with error: `"Configuration file not found: quotez.toml"`

2. **TOML Parsing**: Parse file structure
   - If malformed TOML: Exit with error: `"TOML parse error: <details>"`

3. **Required Field Check**: Verify `quotes.directories` exists
   - If missing: Exit with error: `"Configuration error: 'quotes.directories' is required"`

4. **Type Validation**: Check all fields have correct types
   - If wrong type: Exit with error: `"Configuration error: '<field>' must be <expected_type>"`

5. **Range Validation**: Check numeric constraints
   - Ports: Must be 1-65535
   - Interval: Must be > 0
   - If violated: Exit with error

6. **Enum Validation**: Check `quotes.mode` is valid enum value
   - If invalid: Exit with error

7. **Default Application**: Apply defaults for missing optional fields
   - Log INFO for each default applied

8. **Network Binding Test**: Attempt to bind TCP/UDP sockets
   - If fails: Exit with error: `"Failed to bind to <host>:<port>: <reason>"`

### Validation Error Behavior

**Fatal Errors (Exit Code 1)**:
- Configuration file missing or unreadable
- TOML parse errors
- Missing required fields (`quotes.directories`)
- Invalid types for any field
- Invalid enum values (`quotes.mode`)
- Port/interval out of range
- Socket binding failures

**Non-Fatal (Use Default + Log WARNING)**:
- Optional fields with invalid types (fallback to default)
- Directories that don't exist (service starts with empty store)

---

## Environment Variable Override (Post-MVP)

**MVP**: No environment variable support

**Post-MVP Consideration**: Allow overrides like:
- `QUOTEZ_TCP_PORT=8017` → Overrides `server.tcp_port`
- `QUOTEZ_DIRECTORIES=/data/quotes:/opt/quotes` → Overrides `quotes.directories`

---

## Configuration Reload (Post-MVP)

**MVP**: No hot reload support

**Behavior**: Changes to `quotez.toml` while service is running are ignored until restart.

**Rationale**: Simplifies MVP implementation, avoids race conditions.

**Post-MVP Consideration**: Add SIGHUP handler to reload configuration dynamically.

---

## Logging Configuration Events

### Startup Logs

**INFO Level**:
```
[2025-12-01T12:34:56Z] INFO config_loaded file=quotez.toml tcp_port=17 udp_port=17 host=0.0.0.0 directories=2 mode=random interval=60
[2025-12-01T12:34:56Z] INFO default_applied field=server.host value=0.0.0.0
[2025-12-01T12:34:56Z] INFO default_applied field=quotes.mode value=random
```

**ERROR Level**:
```
[2025-12-01T12:34:56Z] ERROR config_error reason="missing required field: quotes.directories"
[2025-12-01T12:34:56Z] ERROR config_error reason="invalid selection mode: 'randum'. Must be one of: random, sequential, random-no-repeat, shuffle-cycle"
[2025-12-01T12:34:56Z] ERROR bind_error host=0.0.0.0 port=17 reason="Address already in use"
```

---

## Testing & Validation

### Configuration Test Cases

| Test Case | Configuration | Expected Behavior |
|-----------|---------------|-------------------|
| Minimal valid | `directories=["/data"]` | Load with all defaults |
| All fields explicit | Full config with all fields | Load with specified values |
| Missing directories | No `quotes.directories` | Exit with error |
| Empty directories array | `directories=[]` | Exit with error |
| Invalid port (0) | `tcp_port=0` | Exit with error |
| Invalid port (99999) | `tcp_port=99999` | Exit with error |
| Invalid mode | `mode="randum"` | Exit with error |
| Negative interval | `interval_seconds=-1` | Exit with error |
| Non-existent directory | `directories=["/nonexistent"]` | Log warning, start with empty store |
| Malformed TOML | Syntax error in file | Exit with error |

### Example Test Script

```bash
#!/bin/bash

# Test 1: Valid minimal config
cat > quotez.toml <<EOF
[quotes]
directories = ["/data/quotes"]
EOF
./quotez  # Should start successfully

# Test 2: Missing required field
cat > quotez.toml <<EOF
[server]
tcp_port = 17
EOF
./quotez  # Should exit with error

# Test 3: Invalid mode
cat > quotez.toml <<EOF
[quotes]
directories = ["/data"]
mode = "invalid_mode"
EOF
./quotez  # Should exit with error
```

---

## Schema Versioning

**Current Version**: 1.0.0 (matches constitution version)

**Future Changes**: Any schema changes require constitution amendment and version bump.

---

## References

- [TOML Specification v1.0.0](https://toml.io/en/v1.0.0)
- quotez Constitution v1.0.0 (Principle V: Configuration)
- Feature Specification: 001-qotd-nanoservice

---

## Changelog

**2025-12-01**: Initial configuration schema definition for MVP
