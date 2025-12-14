# Data Model: QOTD Nanoservice

**Feature**: 001-qotd-nanoservice  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This document defines the core data entities, their relationships, lifecycle state machines, and invariants for the quotez QOTD nanoservice implementation.

## Core Entities

### 1. Quote

**Description**: A single immutable text string loaded from a source file and stored in memory for serving.

**Attributes**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `content` | `[]const u8` | UTF-8 encoded, 1-512 bytes (typical) | Normalized quote text with whitespace trimmed |
| `hash` | `[32]u8` | Blake3 hash | Content-based identifier for deduplication |
| `source_path` | `?[]const u8` | Valid file path or null | Optional reference to source file (for debugging/logging) |

**Invariants**:
- `content` MUST be valid UTF-8 after normalization
- `content` MUST NOT be empty (empty quotes filtered during parsing)
- `content` MUST NOT contain only whitespace (filtered during parsing)
- `hash` MUST be derived from normalized `content` via Blake3

**Lifecycle**:
```
┌─────────┐
│ Parsed  │ ──► Quote created from file, whitespace trimmed, UTF-8 validated
└────┬────┘
     │
     ▼
┌─────────┐
│ Hashed  │ ──► Blake3 hash computed for deduplication check
└────┬────┘
     │
     ├──► [Duplicate Detected] ──► Discarded (not added to store)
     │
     ▼
┌─────────┐
│ Stored  │ ──► Added to QuoteStore.quotes list, available for selection
└────┬────┘
     │
     ▼
┌─────────┐
│ Served  │ ──► Content sent to client via TCP/UDP (quote remains in store)
└─────────┘
```

**Relationships**:
- Many Quotes → One QuoteStore (contained in)
- One Quote → One QuoteFile (sourced from)
- One Quote → Many NetworkResponses (served in)

---

### 2. QuoteStore

**Description**: In-memory collection of all loaded quotes with selection state management.

**Attributes**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `quotes` | `[][]const u8` | Dynamic array, 0-N elements | All loaded quotes (deduplicated) |
| `selector` | `Selector` | Non-null | Current selection mode and state |
| `allocator` | `std.mem.Allocator` | Non-null | Memory allocator for quote storage |
| `last_rebuild` | `i64` | Unix timestamp | When the store was last rebuilt |
| `metadata` | `StoreMetadata` | Non-null | Statistics about loaded quotes |

**Sub-structure: StoreMetadata**:

| Field | Type | Description |
|-------|------|-------------|
| `total_files_parsed` | `usize` | Number of source files processed |
| `total_quotes_loaded` | `usize` | Total quotes parsed (pre-dedup) |
| `duplicates_removed` | `usize` | Quotes filtered by deduplication |
| `unique_quotes` | `usize` | Final count in `quotes` array |

**Invariants**:
- `quotes.len == metadata.unique_quotes`
- `metadata.total_quotes_loaded >= metadata.unique_quotes`
- `metadata.duplicates_removed == metadata.total_quotes_loaded - metadata.unique_quotes`
- `selector.mode` MUST match the configured selection mode
- Empty store is valid: `quotes.len == 0` when no valid quotes parsed

**State Machine**:
```
┌────────────┐
│ Uninitialized │ ──► Service startup, allocator acquired
└──────┬─────┘
       │
       ▼
┌────────────┐
│ Building   │ ──► Parsing files, hashing, deduplicating
└──────┬─────┘
       │
       ├──► [Empty Result] ──► EmptyReady (quotes.len == 0, log warning)
       │
       ▼
┌────────────┐
│ Ready      │ ──► Quotes available, selector initialized
└──────┬─────┘
       │
       ├──► [Poll Detects Changes] ──► Rebuilding (old store active)
       │                                       │
       │                                       ▼
       │                              ┌────────────┐
       │                              │ Swapping   │ ──► Atomic pointer swap
       │                              └──────┬─────┘
       │                                     │
       │◄────────────────────────────────────┘
       │
       ▼
┌────────────┐
│ Serving    │ ──► Selector.next() called per request
└────────────┘
```

**Operations**:
- `build(directories: []const []const u8) !void` – Parse files, deduplicate, populate store
- `next() ?[]const u8` – Delegate to Selector.next()
- `isEmpty() bool` – Check if quotes.len == 0
- `deinit()` – Free all allocated memory

---

### 3. Selector

**Description**: Encapsulates quote selection logic and mode-specific state.

**Attributes**:

| Field | Type | Description |
|-------|------|-------------|
| `mode` | `SelectionMode` | Enum: random, sequential, random_no_repeat, shuffle_cycle |
| `state` | `union(SelectionMode)` | Tagged union holding mode-specific state |

**SelectionMode Enum**:
```zig
const SelectionMode = enum {
    random,           // Pure random (may repeat immediately)
    sequential,       // Linear order with wraparound
    random_no_repeat, // Random without repeats until exhaustion
    shuffle_cycle,    // Shuffled order, reshuffle on exhaustion/rebuild
};
```

**State Union**:
```zig
const SelectorState = union(SelectionMode) {
    random: void,  // Stateless
    sequential: struct { position: usize },
    random_no_repeat: struct { 
        exhausted: std.AutoHashMap(usize, void),
        rng: std.rand.DefaultPrng,
    },
    shuffle_cycle: struct {
        order: []usize,         // Shuffled indices
        position: usize,        // Current position in shuffled order
        rng: std.rand.DefaultPrng,
    },
};
```

**Invariants**:
- `sequential.position` MUST be < quotes.len (wraps to 0 when incremented at boundary)
- `random_no_repeat.exhausted.count()` MUST be <= quotes.len
- `shuffle_cycle.order.len` MUST equal quotes.len
- `shuffle_cycle.position` MUST be < order.len

**State Machine (per mode)**:

**Sequential**:
```
┌──────────┐
│ position │ ──► Initialized to 0
└─────┬────┘
      │
      ▼
┌──────────┐
│ Serving  │ ──► Return quotes[position], increment position
└─────┬────┘
      │
      ├──► [position == quotes.len] ──► Wrap to 0
      │
      └──► [Rebuild Detected] ──► Reset to 0
```

**Random-No-Repeat**:
```
┌──────────┐
│ Empty Set│ ──► exhausted.count() == 0
└─────┬────┘
      │
      ▼
┌──────────┐
│ Selecting│ ──► Random index not in exhausted set
└─────┬────┘
      │
      ├──► Add index to exhausted set
      │
      ├──► [exhausted.count() == quotes.len] ──► Clear exhausted, restart
      │
      └──► [Rebuild Detected] ──► Clear exhausted
```

**Shuffle-Cycle**:
```
┌──────────┐
│ Shuffling│ ──► Fisher-Yates shuffle of indices [0..quotes.len)
└─────┬────┘
      │
      ▼
┌──────────┐
│ Serving  │ ──► Return quotes[order[position]], increment position
└─────┬────┘
      │
      ├──► [position == order.len] ──► Reshuffle, reset position to 0
      │
      └──► [Rebuild Detected] ──► Reshuffle, reset position to 0
```

---

### 4. Configuration

**Description**: Immutable service configuration loaded from TOML file at startup.

**Attributes**:

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `tcp_port` | `u16` | 1-65535 | TCP listen port (default: 17) |
| `udp_port` | `u16` | 1-65535 | UDP listen port (default: 17) |
| `host` | `[]const u8` | Valid IP address or hostname | Bind address (default: "0.0.0.0") |
| `directories` | `[][]const u8` | Non-empty array | Quote source directories (required) |
| `polling_interval` | `u32` | > 0 | Polling interval in seconds (default: 60) |
| `selection_mode` | `SelectionMode` | Valid enum value | Quote selection mode (default: random) |

**Invariants**:
- `directories.len > 0` (fatal error on startup if missing)
- `tcp_port` and `udp_port` MAY be the same (kernel allows dual-stack binding)
- `polling_interval` MUST be positive (enforce minimum of 1 second)
- All directory paths MUST exist at startup (non-fatal warning if missing, service continues)

**Lifecycle**:
```
┌────────────┐
│ File Read  │ ──► Read quotez.toml from disk
└──────┬─────┘
       │
       ▼
┌────────────┐
│ Parsing    │ ──► TOML parser converts to Configuration struct
└──────┬─────┘
       │
       ├──► [Parse Error] ──► Log error, exit with code 1
       │
       ▼
┌────────────┐
│ Validation │ ──► Check required fields, validate types/ranges
└──────┬─────┘
       │
       ├──► [Missing Required Field] ──► Log error, exit with code 1
       ├──► [Invalid Optional Field] ──► Use default, log warning
       │
       ▼
┌────────────┐
│ Loaded     │ ──► Immutable configuration active for service lifetime
└────────────┘
```

**No Hot Reload**: Configuration changes require service restart (MVP constraint).

---

### 5. FileWatcher

**Description**: Polling mechanism for detecting file system changes in quote directories.

**Attributes**:

| Field | Type | Description |
|-------|------|-------------|
| `directories` | `[][]const u8` | Monitored directories (from Configuration) |
| `interval` | `u32` | Polling interval in seconds |
| `snapshots` | `std.StringHashMap(FileSnapshot)` | Map of file path → last known state |
| `last_poll` | `i64` | Unix timestamp of last poll cycle |

**Sub-structure: FileSnapshot**:

| Field | Type | Description |
|-------|------|-------------|
| `path` | `[]const u8` | Absolute file path |
| `mtime` | `i128` | Modification time (nanoseconds since epoch) |
| `size` | `u64` | File size in bytes (optional change detection hint) |

**Invariants**:
- `snapshots` contains entries for all files found in previous poll
- New files (not in snapshots) are always considered "changed"
- Deleted files (in snapshots but not found) trigger rebuild

**State Machine**:
```
┌────────────┐
│ Initialized│ ──► Initial scan of directories
└──────┬─────┘
       │
       ▼
┌────────────┐
│ Waiting    │ ──► Sleep until next poll interval
└──────┬─────┘
       │
       ▼
┌────────────┐
│ Scanning   │ ──► Walk directories, stat() all files
└──────┬─────┘
       │
       ├──► Compare mtime/size with snapshots
       │
       ├──► [No Changes] ──► Update last_poll, return to Waiting
       │
       ▼
┌────────────┐
│ Changed    │ ──► Return true to trigger rebuild
└──────┬─────┘
       │
       ▼
[QuoteStore Rebuild Initiated]
```

**Operations**:
- `poll() !bool` – Check for changes, return true if rebuild needed
- `updateSnapshots()` – Refresh snapshot map after successful rebuild

---

### 6. NetworkServer

**Description**: Dual TCP/UDP server managing socket I/O and client interactions.

**Attributes**:

| Field | Type | Description |
|-------|------|-------------|
| `tcp_socket` | `std.net.StreamServer` | TCP listener socket |
| `udp_socket` | `std.os.socket_t` | UDP socket (raw file descriptor) |
| `tcp_addr` | `std.net.Address` | Resolved TCP bind address |
| `udp_addr` | `std.net.Address` | Resolved UDP bind address |
| `poll_fds` | `[2]std.os.pollfd` | Poll set for multiplexing |
| `quote_store` | `*QuoteStore` | Pointer to shared quote store |

**Invariants**:
- Both sockets MUST be non-blocking
- `poll_fds[0]` corresponds to TCP, `poll_fds[1]` to UDP
- `quote_store` pointer MUST remain valid (updated atomically during rebuild)

**State Machine**:
```
┌────────────┐
│ Bound      │ ──► Sockets created and bound to host:port
└──────┬─────┘
       │
       ▼
┌────────────┐
│ Listening  │ ──► TCP in listen mode, UDP ready for recvfrom
└──────┬─────┘
       │
       ▼
┌────────────┐
│ Polling    │ ──► poll() syscall with timeout (polling interval)
└──────┬─────┘
       │
       ├──► [Timeout] ──► Check file watcher, continue polling
       │
       ├──► [TCP Ready] ──► AcceptingTCP
       │                         │
       │                         ▼
       │                  ┌────────────┐
       │                  │ SendingTCP │ ──► Send quote, close connection
       │                  └──────┬─────┘
       │                         │
       │◄────────────────────────┘
       │
       ├──► [UDP Ready] ──► ReceivingUDP
       │                         │
       │                         ▼
       │                  ┌────────────┐
       │                  │ SendingUDP │ ──► sendto() with quote, return to polling
       │                  └──────┬─────┘
       │                         │
       │◄────────────────────────┘
       │
       ▼
[Continue Polling Loop]
```

**Operations**:
- `listen() !void` – Bind and listen on TCP/UDP
- `serve() !void` – Event loop: poll(), accept/recv, send quotes
- `handleTCP(conn: std.net.StreamServer.Connection)` – Send quote, close
- `handleUDP(buf: []u8, addr: std.net.Address)` – sendto() response

---

## Entity Relationships

```
┌───────────────┐
│ Configuration │ (loaded once at startup)
└───────┬───────┘
        │
        ├──────► directories[] ──────┐
        │                            │
        ▼                            │
┌───────────────┐                   │
│ NetworkServer │                   │
└───────┬───────┘                   │
        │                            │
        ├──► quote_store (pointer)  │
        │                            │
        ▼                            ▼
┌───────────────┐           ┌───────────────┐
│  QuoteStore   │◄──────────│ FileWatcher   │ (polls for changes)
└───────┬───────┘           └───────────────┘
        │
        ├──► quotes[] (array of Quote.content)
        ├──► selector (Selector instance)
        │
        ▼
┌───────────────┐
│   Selector    │ (manages selection state)
└───────────────┘
```

**Dependency Flow**:
1. **Configuration** → NetworkServer (host/port)
2. **Configuration** → FileWatcher (directories, interval)
3. **Configuration** → QuoteStore (selection_mode)
4. **FileWatcher** → QuoteStore (triggers rebuild)
5. **QuoteStore** → NetworkServer (quote_store pointer for serving)

**Concurrency Model**: Single-threaded
- No mutexes required (sequential processing)
- QuoteStore rebuild uses double-buffering (build new, swap pointer atomically)
- NetworkServer polls with timeout to periodically check FileWatcher

---

## Data Flow Diagrams

### 1. Quote Loading Flow

```
[Configuration]
     │
     ├──► directories[] = ["/data/quotes"]
     │
     ▼
[FileWatcher.poll()]
     │
     ├──► Walk directories, find: "quotes.json", "wisdom.txt"
     │
     ▼
[QuoteStore.build()]
     │
     ├──► Parse quotes.json ──► ["Quote A", "Quote B", "Quote A"]
     ├──► Parse wisdom.txt   ──► ["Quote C", "Quote B"]
     │
     ├──► Hash each quote:
     │    • "Quote A" → hash_a (appears 2x → deduplicate to 1)
     │    • "Quote B" → hash_b (appears 2x → deduplicate to 1)
     │    • "Quote C" → hash_c
     │
     ▼
[QuoteStore.quotes] = ["Quote A", "Quote B", "Quote C"]  (3 unique)
[QuoteStore.metadata]:
    total_files_parsed = 2
    total_quotes_loaded = 5
    duplicates_removed = 2
    unique_quotes = 3
```

### 2. Request Serving Flow (TCP)

```
[Client] ──connect──► [NetworkServer.tcp_socket]
                             │
                             ▼
                      [poll() returns TCP_READY]
                             │
                             ▼
                      [accept() connection]
                             │
                             ▼
                      [QuoteStore.next()]
                             │
                             ├──► [selector.mode == random]
                             │         │
                             │         ▼
                             │    [rand() % quotes.len] → index 1
                             │
                             ▼
                      Return "Quote B"
                             │
                             ▼
                      [send("Quote B\n")]
                             │
                             ▼
                      [close() connection]
```

### 3. Rebuild Trigger Flow

```
[FileWatcher.poll()] at interval
     │
     ├──► stat("/data/quotes/quotes.json")
     │    • mtime_current = 1701450000
     │    • mtime_snapshot = 1701440000
     │    • CHANGED!
     │
     ▼
[Return true to NetworkServer]
     │
     ▼
[QuoteStore.build()] (async/background)
     │
     ├──► Build new QuoteStore instance
     ├──► Parse all files again
     ├──► Deduplicate
     │
     ▼
[Atomic Pointer Swap]
     │
     ├──► Old store continues serving until swap
     ├──► New store becomes active
     │
     ▼
[Selector Reset]
     │
     ├──► sequential → position = 0
     ├──► random_no_repeat → clear exhausted
     ├──► shuffle_cycle → reshuffle order
```

---

## Memory Management

### Allocation Strategy

**Arena Pattern for Quote Loading**:
```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit(); // Bulk-free all quotes at once during rebuild

const allocator = arena.allocator();
// Parse files, allocate quotes, hashes, etc.
```

**Ownership Rules**:
- `QuoteStore` owns `quotes[]` array and all quote content strings
- `Selector` owns mode-specific state (exhausted sets, shuffle order)
- `Configuration` owns directory/host strings (lifetime = entire process)
- `FileWatcher` owns snapshot map (updated each poll)

**Deallocation Points**:
- Quote store rebuild: Old arena freed, new arena created
- Service shutdown: All allocators freed via defer chains
- Selector reset: Mode-specific state cleared/reallocated

---

## Performance Characteristics

| Operation | Time Complexity | Space Complexity | Notes |
|-----------|-----------------|------------------|-------|
| Quote deduplication | O(n) | O(n) | Blake3 hash + HashMap lookup |
| Random selection | O(1) | O(1) | Direct index access |
| Sequential selection | O(1) | O(1) | Increment counter |
| Random-no-repeat | O(k) worst case | O(n) | k = attempts to find non-exhausted |
| Shuffle-cycle | O(n) on reshuffle | O(n) | Fisher-Yates algorithm |
| File change detection | O(f) | O(f) | f = number of files, stat() each |
| Quote store rebuild | O(n + f) | O(n) | Parse + deduplicate |

---

## Validation Rules

### Quote Validation
- MUST be valid UTF-8 (replacement chars for invalid sequences)
- MUST have length > 0 after trimming
- MUST NOT be only whitespace

### Configuration Validation
- `directories` MUST be non-empty array
- Ports MUST be in range [1, 65535]
- `polling_interval` MUST be positive integer
- `selection_mode` MUST match enum values exactly (case-sensitive)

### Runtime Invariants
- `QuoteStore.quotes.len == QuoteStore.metadata.unique_quotes` (always)
- `Selector` state indices MUST be < `quotes.len` (prevents index OOB)
- Empty quote store is valid but logged as WARNING

---

## Error Handling

### Fatal Errors (Exit Process)
- Configuration file missing or unreadable
- Required configuration fields (directories) missing or invalid type
- Cannot bind to TCP/UDP ports (already in use, permissions)

### Non-Fatal Errors (Log and Continue)
- Malformed quote file (skip file, continue loading)
- Individual quote parsing failure (skip quote, continue parsing)
- File system errors during polling (log, retry next interval)
- Empty quote store after loading (serve empty responses)

### Graceful Degradation
- Empty quote store: Serve empty responses, log warning
- All files malformed: Empty store, service continues running
- Network errors: Log, continue serving other requests

---

## Testing Strategies

### Unit Test Coverage
- **Quote**: Normalization, UTF-8 validation, hashing
- **QuoteStore**: Deduplication correctness, rebuild atomicity
- **Selector**: Each mode's selection algorithm, wraparound, reset behavior
- **Configuration**: Parsing valid/invalid TOML, defaults, validation
- **FileWatcher**: Change detection with mtime/size variations

### Integration Test Coverage
- **End-to-End Loading**: Place files → verify quotes loaded → deduplicated
- **Selection Mode Behavior**: Configure mode → request N quotes → verify pattern
- **Reload Cycle**: Start service → modify files → wait interval → verify rebuild
- **Network Protocol**: TCP/UDP requests → verify RFC 865 compliance

### Property-Based Testing
- **Random Mode**: Over 1000 requests, verify all indices valid
- **Sequential Mode**: Verify exactly one full cycle returns all quotes in order
- **Shuffle-Cycle**: Verify reshuffle produces different order, all quotes served once per cycle

---

## Conclusion

This data model provides a complete blueprint for implementing the quotez QOTD nanoservice. All entities are well-defined with clear invariants, state transitions, and relationships. The single-threaded architecture with atomic pointer swapping for reloads ensures simplicity without sacrificing correctness.

**Next Steps**: Proceed to contracts/ directory creation for protocol specifications and configuration schema.
