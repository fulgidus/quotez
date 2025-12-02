# Research: QOTD Nanoservice Implementation

**Feature**: 001-qotd-nanoservice  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This document captures research findings and technical decisions for implementing the quotez QOTD nanoservice in Zig. All NEEDS CLARIFICATION items from Technical Context have been resolved.

## Zig Language & Toolchain

### Decision: Zig 0.13.0 (Latest Stable)

**Rationale**:
- Zig 0.13.0 is the current stable release (as of Dec 2025)
- Provides stable standard library APIs for networking, file I/O, and crypto
- Strong support for static linking with musl libc
- Cross-compilation to Linux x86_64/aarch64 out of the box
- Built-in test framework eliminates external dependencies

**Alternatives Considered**:
- Zig 0.12.x: Older stable, but missing recent std.net improvements
- Zig master/nightly: Too unstable for production MVP

**Build Configuration**:
```zig
// build.zig snippet
const target = b.standardTargetOptions(.{
    .default_target = .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    },
});
const optimize = b.standardOptimizeOption(.{
    .preferred_optimize_mode = .ReleaseSmall,
});
```

## Networking Architecture

### Decision: Single-threaded Event Loop with std.net

**Rationale**:
- Zig's `std.net` provides non-blocking socket I/O primitives
- Single-threaded model eliminates concurrency bugs for MVP
- `std.os.poll()` or `std.os.epoll()` for multiplexing TCP and UDP sockets
- Simplifies quote store access (no mutex needed)
- Adequate for 100 concurrent connections at low request rates

**Implementation Approach**:
1. Create TCP and UDP sockets, set to non-blocking mode
2. Use `std.os.poll()` with both sockets in the poll set
3. On TCP ready: accept connection, send quote, close socket
4. On UDP ready: recvfrom, sendto with quote
5. Poll timeout set to polling interval for file watcher

**Alternatives Considered**:
- Multi-threaded with thread pool: Overkill for expected load, adds complexity
- async/await (Zig's experimental feature): Not stable in 0.13.0
- External event loop (libuv): Violates zero-dependency requirement

## File Format Parsing

### Decision: Format Detection Order via Extension + Content Sniffing

**Detection Chain**:
1. **JSON**: Check extension `.json`, validate first non-whitespace char is `{` or `[`
2. **CSV**: Check extension `.csv`, look for comma/tab delimiters in first line
3. **TOML**: Check extension `.toml`, look for `[section]` or `key = value` patterns
4. **YAML**: Check extension `.yaml` or `.yml`, look for `---` or key-colon patterns
5. **Plaintext**: Fallback—split by newlines, trim whitespace

**Parsing Strategy**:
- **JSON**: Use `std.json.parseFromSlice()` for array or object of strings
- **CSV**: Custom parser—split lines by delimiters, extract quote column (first by default)
- **TOML**: Inline minimal parser or use `zig-toml` package if available
- **YAML**: Inline minimal parser (subset: lists of strings only)
- **TXT**: `std.mem.split(u8, content, "\n")` with trimming

**Rationale**:
- Extension check is fast and sufficient for 99% of cases
- Content sniffing provides fallback for misnamed files
- Inline parsers for TOML/YAML keep binary size small
- Error tolerance achieved by catching parse errors and logging skipped files

**Alternatives Considered**:
- External parsing libraries: Violates zero-dependency goal
- Magic number detection: Unnecessary complexity for text formats
- Strict extension-only: Less user-friendly, fails on misnamed files

## Quote Deduplication

### Decision: Blake3 Hashing via std.crypto

**Rationale**:
- Zig's `std.crypto.hash.Blake3` is fast, built-in, and produces 32-byte hashes
- Collision resistance sufficient for 10k quote corpus
- Hash quote content (after normalization) to detect duplicates
- Store hashes in `std.HashMap(Blake3Digest, void)` for O(1) lookup

**Implementation**:
```zig
const Blake3 = std.crypto.hash.Blake3;
var seen = std.AutoHashMap([32]u8, void).init(allocator);

fn addQuote(content: []const u8) !void {
    var hash: [32]u8 = undefined;
    Blake3.hash(content, &hash, .{});
    
    if (seen.contains(hash)) {
        // Duplicate, skip
        return;
    }
    try seen.put(hash, {});
    try quotes.append(content);
}
```

**Alternatives Considered**:
- SHA256: Slower, no benefit for this use case
- MD5: Deprecated, collision concerns
- String equality: O(n*m) performance for large corpuses

## Quote Selection Modes

### Decision: Strategy Pattern with Function Pointers

**Architecture**:
```zig
const SelectionMode = enum { random, sequential, random_no_repeat, shuffle_cycle };

const Selector = struct {
    mode: SelectionMode,
    state: union(SelectionMode) {
        random: void,
        sequential: usize, // current position
        random_no_repeat: std.AutoHashMap(usize, void), // exhausted indices
        shuffle_cycle: struct { order: []usize, position: usize },
    },
    
    fn next(self: *Selector, quotes: []const []const u8) ?[]const u8 {
        return switch (self.mode) {
            .random => self.selectRandom(quotes),
            .sequential => self.selectSequential(quotes),
            .random_no_repeat => self.selectRandomNoRepeat(quotes),
            .shuffle_cycle => self.selectShuffleCycle(quotes),
        };
    }
};
```

**Rationale**:
- Tagged union cleanly represents mode-specific state
- Single `next()` interface simplifies server logic
- Mode behavior encapsulated in dedicated functions
- State reset on quote store rebuild handled by recreating Selector

**Alternatives Considered**:
- Object-oriented with vtables: More verbose in Zig
- Global state machine: Harder to test and reason about

## File System Watching

### Decision: Polling with stat() + mtime Comparison

**Implementation**:
```zig
const FileSnapshot = struct {
    path: []const u8,
    mtime: i128, // nanoseconds since epoch
};

fn pollDirectories(dirs: []const []const u8) !bool {
    var changed = false;
    for (dirs) |dir| {
        var iter = try std.fs.cwd().openIterableDir(dir, .{});
        defer iter.close();
        
        var walker = try iter.walk(allocator);
        defer walker.deinit();
        
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            const stat = try entry.dir.statFile(entry.basename);
            const mtime = stat.mtime;
            
            if (last_snapshot.get(entry.path)) |old_mtime| {
                if (mtime > old_mtime) {
                    changed = true;
                }
            } else {
                changed = true; // new file
            }
            try last_snapshot.put(entry.path, mtime);
        }
    }
    return changed;
}
```

**Rationale**:
- `stat()` is portable across Linux file systems
- mtime comparison is simple and reliable
- HashMap stores last-known mtime for each file
- Polling interval (default 60s) balances responsiveness vs CPU usage

**Alternatives Considered**:
- inotify: Linux-specific, adds complexity, not portable
- Content hashing: More expensive than mtime check
- Directory-level mtime: Doesn't detect file modifications

## Configuration Parsing

### Decision: Minimal TOML Parser or zig-toml Package

**Config Schema**:
```toml
[server]
tcp_port = 17
udp_port = 17
host = "0.0.0.0"

[quotes]
directories = ["/data/quotes", "/etc/quotez/custom"]
mode = "random" # random | sequential | random-no-repeat | shuffle-cycle

[polling]
interval_seconds = 60
```

**Parsing Approach**:
1. Load file with `std.fs.cwd().readFileAlloc()`
2. Parse TOML with `std.json`-style API (if zig-toml available) or inline parser
3. Validate required fields (directories)
4. Apply defaults for optional fields
5. Validate types and ranges (ports 1-65535, positive intervals, valid mode enum)

**Rationale**:
- TOML is human-readable and self-documenting
- Zig has no built-in TOML parser, but zig-toml or inline solution works
- Strict validation prevents runtime errors from bad config

**Alternatives Considered**:
- JSON config: Less human-friendly for comments and readability
- YAML config: Overly complex for simple key-value structure
- Command-line args only: Doesn't scale for multiple directories

## Logging Strategy

### Decision: Minimal Structured Logging to stdout

**Log Format**:
```
[2025-12-01T12:34:56Z] INFO service_start version=1.0.0
[2025-12-01T12:34:56Z] INFO config_loaded tcp_port=17 udp_port=17 directories=2 mode=random interval=60
[2025-12-01T12:34:57Z] INFO quote_store_built files=15 quotes=523 duplicates_removed=12
[2025-12-01T12:35:00Z] WARN empty_quote_store directories=2
[2025-12-01T12:36:00Z] ERROR config_parse_error path=/quotez.toml reason="missing required field: directories"
```

**Implementation**:
```zig
fn log(level: Level, event: []const u8, fields: anytype) !void {
    const timestamp = std.time.timestamp();
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("[{d}] {s} {s}", .{ timestamp, @tagName(level), event });
    inline for (std.meta.fields(@TypeOf(fields))) |field| {
        try stdout.print(" {s}={any}", .{ field.name, @field(fields, field.name) });
    }
    try stdout.print("\n", .{});
}
```

**Rationale**:
- stdout is standard for containerized services (captured by Docker/k8s)
- Structured key-value pairs enable log parsing
- ISO 8601 timestamps with UTC for consistency
- No external logging library needed

**Alternatives Considered**:
- JSON log lines: More verbose, harder for humans to read
- syslog: Requires external daemon, violates simplicity goal
- Silent operation: Insufficient for debugging production issues

## Testing Strategy

### Unit Tests

**Approach**: Co-located test blocks within source files using `test "name" { ... }` syntax

**Coverage**:
- **config.zig**: Valid/invalid TOML parsing, default application, validation rules
- **quote_store.zig**: Deduplication logic, selection mode algorithms
- **parsers/*.zig**: Each format's parsing edge cases (malformed input, empty files)
- **selector.zig**: Mode-specific selection correctness (sequential wrapping, shuffle uniqueness)

**Example**:
```zig
test "sequential mode wraps to position 0" {
    var selector = Selector.init(.sequential);
    const quotes = &[_][]const u8{ "a", "b", "c" };
    
    try std.testing.expectEqualStrings("a", selector.next(quotes).?);
    try std.testing.expectEqualStrings("b", selector.next(quotes).?);
    try std.testing.expectEqualStrings("c", selector.next(quotes).?);
    try std.testing.expectEqualStrings("a", selector.next(quotes).?); // wrap
}
```

### Integration Tests

**Approach**: Separate `tests/integration/` directory with subprocess spawning

**Coverage**:
- **protocol_test.zig**: Spawn service, connect via TCP/UDP, verify RFC 865 behavior
- **reload_test.zig**: Start service, modify quote files, verify changes reflected
- **end_to_end_test.zig**: Full lifecycle from startup to graceful shutdown

**Example**:
```zig
test "TCP QOTD sends one quote and closes" {
    // Start quotez subprocess
    const proc = try std.ChildProcess.init(&[_][]const u8{"./zig-out/bin/quotez"}, allocator);
    try proc.spawn();
    defer _ = proc.kill() catch {};
    
    std.time.sleep(500 * std.time.ns_per_ms); // Wait for startup
    
    // Connect via TCP
    const stream = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 17);
    defer stream.close();
    
    var buf: [512]u8 = undefined;
    const len = try stream.read(&buf);
    
    try std.testing.expect(len > 0);
    try std.testing.expect(len < 512);
    
    // Verify connection closed
    const len2 = try stream.read(&buf);
    try std.testing.expectEqual(@as(usize, 0), len2);
}
```

## Performance Considerations

### Memory Allocation

**Strategy**:
- Use `std.heap.GeneralPurposeAllocator` for development/testing
- Use `std.heap.c_allocator` for production (backed by musl malloc)
- Arena allocator for quote loading (bulk allocate, bulk free)

### Binary Size Optimization

**Techniques**:
- `ReleaseSmall` optimization mode (trades speed for size)
- Strip debug symbols: `strip ./zig-out/bin/quotez`
- Link-time optimization (LTO) enabled by default in Zig
- Single-file binary with no shared libraries

**Expected Size**: 2-4MB for static musl binary

### Startup Time Optimization

**Techniques**:
- Lazy initialization: Don't parse all files synchronously at startup
- Parallel file reading if needed (spawn threads for parsing, merge results)
- Memory-mapped file I/O for large quote files (optional optimization)

## Dependencies Summary

**Zig Standard Library Only**:
- `std.net`: TCP/UDP socket I/O
- `std.fs`: File system operations
- `std.crypto.hash.Blake3`: Content hashing
- `std.json`: JSON parsing
- `std.mem`: Memory utilities
- `std.os`: Low-level OS interfaces (poll, stat)
- `std.time`: Timestamps and timers

**Zero External Dependencies**: All functionality achieved with Zig stdlib

## Build & Deployment

### Build Commands

```bash
# Development build
zig build

# Release build (static, optimized for size)
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl

# Run tests
zig build test

# Cross-compile for ARM64
zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-linux-musl
```

### Docker Image

```dockerfile
FROM scratch
COPY zig-out/bin/quotez /quotez
COPY quotez.toml /quotez.toml
ENTRYPOINT ["/quotez"]
```

**Image Size**: ~5-10MB (binary + config + minimal quotes for demo)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Zig 0.13 API changes | Low | Medium | Pin to exact version, test thoroughly |
| TOML parsing complexity | Medium | Low | Use zig-toml package or inline simple parser |
| Event loop performance | Low | Medium | Profile with realistic load, add threading if needed |
| Static linking issues | Low | High | Test on target Linux distros early |
| Quote file encoding issues | Medium | Low | Normalize to UTF-8, log warnings for invalid chars |

## Open Questions (Resolved)

All NEEDS CLARIFICATION items from Technical Context have been resolved:
- ✅ Language/Version: Zig 0.13.0 confirmed
- ✅ Dependencies: Zig stdlib only (zero external deps)
- ✅ Testing: Built-in Zig test framework
- ✅ Target Platform: Linux x86_64/aarch64 with musl libc
- ✅ Performance Goals: Confirmed achievable with single-threaded architecture
- ✅ Constraints: Static binary and scratch container confirmed feasible

## Next Steps

Proceed to **Phase 1: Design & Contracts**:
1. Generate `data-model.md` with entity definitions and state machines
2. Create `contracts/` directory with protocol specs and config schema
3. Write `quickstart.md` for deployment and usage guide
4. Update agent context with Zig-specific information
