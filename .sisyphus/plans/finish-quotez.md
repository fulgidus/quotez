# Finish quotez — Complete Zig 0.16 Migration, Missing Features & Future Ideas

## TL;DR

> **Quick Summary**: Complete the quotez QOTD nanoservice by finishing the Zig 0.16 migration (networking rewrite, bug fixes), implementing hot reload (FileWatcher), polishing for Docker deployment, and creating an IDEAS.md with future feature plans.
>
> **Deliverables**:
> - Fully compiling and passing codebase on Zig 0.16.0
> - TCP and UDP servers rewritten for Zig 0.16 networking API
> - Selector and QuoteStore bugs fixed
> - Integration tests fixed and passing
> - FileWatcher (hot reload) implemented
> - Docker image building correctly from scratch
> - Static binary verified < 5MB, Docker image < 10MB
> - IDEAS.md with future feature roadmap
> - All spec documents updated to reference Zig 0.16.0
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 5 waves
> **Critical Path**: T1 (selector fix) → T2 (QuoteStore.add) → T3 (tcp rewrite) → T4 (udp rewrite) → T5 (main.zig) → T8 (zig build) → T10 (FileWatcher) → T14 (static binary) → T16 (Docker) → F1-F4

---

## Context

### Original Request
User asked to "finish everything" — complete the Zig 0.16 migration, implement all missing features (hot reload, polish), and create an IDEAS.md with future development ideas (backoffice web UI, quote categorization/tagging, holiday-aware serving).

### Interview Summary
**Key Discussions**:
- Migration from Zig 0.13 → 0.16 is ~70% complete (data layer done, networking blocked)
- `std.net` was removed entirely in Zig 0.16; servers need full rewrite using `std.posix` socket APIs
- Selector has undefined `initWithSeed` function and memory management bugs
- Integration tests reference non-existent `QuoteStore.add()` and `QuoteStore.addQuote()` methods
- Docker has port mismatch: EXPOSE 8017 vs config port 17
- User explicitly said: "Do not worry about docker image actual distribution (like artifacthub)"
- User explicitly said: "just make a good server and make it work perfectly"
- User explicitly said: "think it to work from inside a docker please"

**Research Findings**:
- Zig 0.16 networking: `std.net.Address` → use `std.posix` directly (socket/bind/listen/accept/sendto/recvfrom all exist in `std.posix`)
- `std.Io.net.IpAddress` exists but requires an `Io` runtime instance — for a simple blocking server, raw `std.posix` socket API is the pragmatic choice
- `std.posix.poll()` still works identically
- Signal handling (`sigaction`, `SIG.TERM`, `SIG.INT`) unchanged
- `std.time.nanoTimestamp()` — needs verification; perf tests use it heavily
- `std.time.Instant.now()` with `.timestamp.sec`/`.nsec` fields confirmed working

### Metis Review
**Identified Gaps** (addressed):
- Missing `try` on `Selector.init()` in main.zig — included in T5
- Event loop references `tcp.socket.stream.handle` which won't exist after rewrite — included in T5
- `errdefer` memory bug in selector shuffle_cycle — included in T1
- Tests import files outside module path — included in T7
- Unused local constants treated as errors — included in T7
- `perf_test.zig` uses `std.time.nanoTimestamp()` and `std.net` — included in T9
- Docker port inconsistency — included in T16

---

## Work Objectives

### Core Objective
Make quotez compile, pass all tests, and run correctly as a Docker-based QOTD server on Zig 0.16.0, with hot reload support and a documented future feature roadmap.

### Concrete Deliverables
- `src/selector.zig` — Fixed with `initWithSeed`, correct memory management
- `src/quote_store.zig` — `add()` and `addQuote()` helper methods
- `src/servers/tcp.zig` — Rewritten for `std.posix` socket API
- `src/servers/udp.zig` — Rewritten for `std.posix` socket API
- `src/main.zig` — Fixed event loop, correct FD handling, `try` on selector init
- `src/watcher.zig` — New FileWatcher for hot reload
- `tests/integration/*.zig` — All fixed and passing
- `Dockerfile` + `quotez.docker.toml` — Consistent port configuration
- `IDEAS.md` — Future features document
- `README.md` + spec docs — Updated to Zig 0.16.0

### Definition of Done
- [ ] `zig build` succeeds with zero errors
- [ ] `zig build test` passes all unit tests
- [ ] `zig build test-all` passes all integration + e2e + perf tests
- [ ] Server responds to TCP connections on configured port (verified with `nc`)
- [ ] Server responds to UDP datagrams on configured port (verified with `nc -u`)
- [ ] `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl` produces static binary < 5MB
- [ ] `docker build -t quotez .` succeeds and image < 10MB
- [ ] `docker run` starts server correctly
- [ ] IDEAS.md exists with documented future features

### Must Have
- RFC 865 compliant TCP and UDP QOTD service
- All 4 selection modes working (random, sequential, random_no_repeat, shuffle_cycle)
- Hot reload via FileWatcher polling
- Static binary for scratch Docker image
- Zero runtime dependencies

### Must NOT Have (Guardrails)
- No Docker distribution/registry setup (user explicitly excluded ArtifactHub)
- No `std.Io.net` high-level API (requires Io runtime — use raw `std.posix` sockets instead for simplicity)
- No async/event-loop frameworks — keep simple blocking + poll() architecture
- No external dependencies — pure Zig stdlib only
- No over-engineered abstractions — keep the nanoservice minimal
- No changes to the TOML config format or quote file formats

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (zig build test, zig build test-all)
- **Automated tests**: Tests-after (fix existing tests, add new ones for FileWatcher)
- **Framework**: Zig built-in test framework
- **Approach**: Fix existing broken tests first, then implement new features with tests

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Server**: Use Bash (nc/curl) — Connect to TCP/UDP ports, verify quote responses
- **Build**: Use Bash — Run zig build, capture output, verify zero errors
- **Docker**: Use Bash — Build image, run container, test connectivity
- **Unit tests**: Use Bash — Run zig build test, verify pass counts

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — fix compile blockers, independent fixes):
├── Task 1: Fix selector.zig — initWithSeed + errdefer memory bug [deep]
├── Task 2: Add QuoteStore.add()/addQuote() helper methods [quick]
├── Task 3: Rewrite tcp.zig for std.posix socket API [deep]
├── Task 4: Rewrite udp.zig for std.posix socket API [deep]
├── Task 6: Create IDEAS.md [writing]
├── Task 12: Update README.md + spec docs to Zig 0.16.0 [writing]

Wave 2 (After Wave 1 — main.zig depends on tcp/udp rewrite):
├── Task 5: Fix main.zig — event loop, selector try, FD refs (depends: 1, 3, 4) [deep]

Wave 3 (After Wave 2 — tests depend on everything compiling):
├── Task 7: Fix end_to_end_test.zig — imports + unused constants (depends: 5) [quick]
├── Task 8: Fix protocol_test.zig — uses store.add() (depends: 2, 5) [quick]
├── Task 9: Fix perf_test.zig — nanoTimestamp + addQuote + std.net (depends: 2, 5) [quick]
├── Task 13: Fix selector_test.zig if needed (depends: 1, 5) [quick]

Wave 4 (After Wave 3 — features + verification):
├── Task 10: Implement FileWatcher in src/watcher.zig (depends: 5) [deep]
├── Task 11: Integrate FileWatcher into main.zig event loop (depends: 5, 10) [deep]
├── Task 14: Verify static binary build + size < 5MB (depends: 8, 9) [quick]
├── Task 15: Run full test suite — zig build test-all (depends: 7, 8, 9, 13) [quick]

Wave 5 (After Wave 4 — Docker + polish):
├── Task 16: Fix Dockerfile + docker config + build image (depends: 14) [quick]
├── Task 17: Performance benchmarks verification (depends: 15) [quick]

Wave FINAL (After ALL tasks — independent review, 4 parallel):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
├── Task F4: Scope fidelity check (deep)

Critical Path: T1 → T5 → T8 → T15 → T16 → F1-F4
Parallel Speedup: ~60% faster than sequential
Max Concurrent: 6 (Wave 1)
```

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|-----------|--------|------|
| T1 | — | T5, T13 | 1 |
| T2 | — | T8, T9 | 1 |
| T3 | — | T5 | 1 |
| T4 | — | T5 | 1 |
| T5 | T1, T3, T4 | T7, T8, T9, T10, T11, T13 | 2 |
| T6 | — | — | 1 |
| T7 | T5 | T15 | 3 |
| T8 | T2, T5 | T14, T15 | 3 |
| T9 | T2, T5 | T14, T15 | 3 |
| T10 | T5 | T11 | 4 |
| T11 | T5, T10 | T15 | 4 |
| T12 | — | — | 1 |
| T13 | T1, T5 | T15 | 3 |
| T14 | T8, T9 | T16 | 4 |
| T15 | T7, T8, T9, T13 | T17 | 4 |
| T16 | T14 | — | 5 |
| T17 | T15 | — | 5 |
| F1-F4 | ALL | — | FINAL |

### Agent Dispatch Summary

- **Wave 1**: **6** — T1 → `deep`, T2 → `quick`, T3 → `deep`, T4 → `deep`, T6 → `writing`, T12 → `writing`
- **Wave 2**: **1** — T5 → `deep`
- **Wave 3**: **4** — T7 → `quick`, T8 → `quick`, T9 → `quick`, T13 → `quick`
- **Wave 4**: **4** — T10 → `deep`, T11 → `deep`, T14 → `quick`, T15 → `quick`
- **Wave 5**: **2** — T16 → `quick`, T17 → `quick`
- **FINAL**: **4** — F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

---

## TODOs

> Implementation + Test = ONE Task. Never separate.
> EVERY task MUST have: Recommended Agent Profile + Parallelization info + QA Scenarios.

- [x] 1. Fix selector.zig — Implement initWithSeed + Fix errdefer Memory Bug

  **What to do**:
  - Implement a `pub fn initWithSeed(allocator: std.mem.Allocator, mode: SelectionMode, quote_count: usize, seed: u64) !Selector` function that constructs a Selector using the provided seed instead of deriving one from `Instant.now()`
  - The function body should replicate the same `switch (mode)` logic already in `init()` but using the `seed` parameter directly
  - Fix the `errdefer allocator.free(order)` bug in the `shuffle_cycle` branch (line ~71): `errdefer` inside the `blk:` scope frees `order` on normal return too, creating a dangling pointer. Change to ensure `order` is only freed on error, not on success path. The `errdefer` should be placed such that it only triggers if the block itself errors, not when it successfully returns via `break :blk`
  - Verify the `std.time.Instant.now()` return type — confirm `.timestamp.sec` and `.timestamp.nsec` field names are correct for Zig 0.16
  - Run `zig build test` after changes to verify selector unit tests pass

  **Must NOT do**:
  - Do not change the Selector public API (init signature, next(), deinit())
  - Do not add external dependencies
  - Do not change selection mode behavior

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Memory management bug requires careful analysis of Zig ownership semantics and errdefer scoping
  - **Skills**: []
    - No special skills needed — pure Zig stdlib work
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4, 6, 12)
  - **Blocks**: Task 5 (main.zig fix), Task 13 (selector_test.zig)
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `src/selector.zig:46-80` — Current `init()` function with the `initWithSeed` call (line 50) and errdefer bug (line 71)
  - `src/selector.zig:7-36` — SelectorState union and state structs (RandomState, SequentialState, RandomNoRepeatState, ShuffleCycleState)
  - `src/selector.zig:39-44` — Selector struct fields that initWithSeed must populate

  **API/Type References**:
  - `src/config.zig:SelectionMode` — The SelectionMode enum used in Selector
  - `~/.zvm/master/lib/std/time.zig` — Verify Instant.now() return type and timestamp field names

  **Test References**:
  - `src/selector.zig` bottom — Existing selector tests (run with `zig build test`)

  **Acceptance Criteria**:
  - [ ] `initWithSeed` function exists and is callable from `init()` fallback
  - [ ] `zig build 2>&1 | grep -c 'error'` returns 0 for selector.zig
  - [ ] No `use of undeclared identifier 'initWithSeed'` error
  - [ ] `zig build test 2>&1` — selector tests pass (no memory leaks reported by test allocator)

  **QA Scenarios:**
  ```
  Scenario: Selector compiles without errors
    Tool: Bash
    Preconditions: Zig 0.16 available at ~/.zvm/master/zig
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Check output does not contain 'error' related to selector.zig
    Expected Result: Build proceeds past selector.zig without errors
    Failure Indicators: 'use of undeclared identifier' or 'error:' mentioning selector.zig
    Evidence: .sisyphus/evidence/task-1-selector-compiles.txt

  Scenario: Selector unit tests pass with no memory leaks
    Tool: Bash
    Preconditions: selector.zig changes applied
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      2. Check for test pass count and absence of 'memory leak' or 'error'
    Expected Result: All selector tests PASS, no leaked memory
    Failure Indicators: 'FAIL', 'leaked', 'error' in output
    Evidence: .sisyphus/evidence/task-1-selector-tests.txt
  ```

  **Commit**: YES
  - Message: `fix(selector): implement initWithSeed and fix errdefer memory bug`
  - Files: `src/selector.zig`
  - Pre-commit: `zig build test`

---

- [x] 2. Add QuoteStore.add() and addQuote() Helper Methods

  **What to do**:
  - Add `pub fn add(self: *QuoteStore, content: []const u8) !void` method to QuoteStore that:
    - Creates a Quote via `Quote.init(self.allocator, content, null)`
    - Checks deduplication against existing quotes using Blake3 hash (iterate `self.quotes.items` and compare `.hash` fields)
    - If not duplicate: appends to `self.quotes` via `self.quotes.append(self.allocator, quote)` and increments `self.metadata.total_quotes_loaded` and `self.metadata.unique_quotes`
    - If duplicate: calls `quote.deinit(self.allocator)` to free, increments `self.metadata.duplicates_removed`
  - Add `pub fn addQuote(self: *QuoteStore, content: []const u8) !void` as a simple alias that calls `self.add(content)`
  - These methods are needed by integration tests (protocol_test.zig calls `store.add()`, perf_test.zig calls `store.addQuote()`)

  **Must NOT do**:
  - Do not change the existing `build()` or `walkDirectory()` methods
  - Do not change the Quote struct
  - Do not add file-based loading to `add()` — it takes raw string content only

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward method addition following existing patterns in the file
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4, 6, 12)
  - **Blocks**: Task 8 (protocol_test.zig), Task 9 (perf_test.zig)
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `src/quote_store.zig:66-90` — QuoteStore struct definition and existing init/deinit methods
  - `src/quote_store.zig:92-138` — `build()` method showing deduplication pattern with `seen` HashMap
  - `src/quote_store.zig:12-55` — Quote struct with `init()` and `deinit()` showing proper memory management

  **API/Type References**:
  - `src/quote_store.zig:11-55` — `Quote.init(allocator, content, source_path)` signature
  - `src/quote_store.zig:67` — `quotes: std.ArrayList(Quote)` — the collection to append to

  **Test References**:
  - `tests/integration/protocol_test.zig:14-23` — `createTestStore()` helper that calls `store.add()` — shows expected API
  - `tests/integration/perf_test.zig:32` — Calls `store.addQuote()` — shows expected alias API

  **Acceptance Criteria**:
  - [ ] `QuoteStore` has public `add()` method accepting `[]const u8`
  - [ ] `QuoteStore` has public `addQuote()` method as alias
  - [ ] Adding same content twice only stores one copy (deduplication)
  - [ ] `store.count()` reflects correct unique count after adds

  **QA Scenarios:**
  ```
  Scenario: add() method exists and works
    Tool: Bash
    Preconditions: quote_store.zig changes applied
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Verify no 'no field or member function named add' errors
    Expected Result: Build proceeds past any file referencing store.add()
    Failure Indicators: 'no field or member function named' in output
    Evidence: .sisyphus/evidence/task-2-add-method.txt

  Scenario: Deduplication works correctly
    Tool: Bash
    Preconditions: quote_store.zig changes applied, unit tests exist in quote_store.zig
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      2. Look for quote_store test results
    Expected Result: Tests pass showing dedup works
    Failure Indicators: 'FAIL' or assertion errors
    Evidence: .sisyphus/evidence/task-2-dedup-test.txt
  ```

  **Commit**: YES
  - Message: `feat(store): add QuoteStore.add() and addQuote() helper methods`
  - Files: `src/quote_store.zig`
  - Pre-commit: `zig build test`

---

- [x] 3. Rewrite TCP Server for Zig 0.16 std.posix Socket API

  **What to do**:
  - Completely rewrite `src/servers/tcp.zig` to use `std.posix` socket API instead of removed `std.net`
  - Replace `std.net.Address` with `std.posix.sockaddr` family:
    - Use `std.posix.getaddrinfo()` or manually construct `std.posix.sockaddr.in` for IPv4
    - Parse host string and port into sockaddr struct
  - Replace `std.net.Server` (address.listen()) with:
    - `std.posix.socket(AF.INET, SOCK.STREAM, IPPROTO.TCP)` → returns `socket_t`
    - `std.posix.setsockopt(sock, SOL.SOCKET, SO.REUSEADDR, ...)` for reuse
    - `std.posix.bind(sock, &addr, addr_len)`
    - `std.posix.listen(sock, backlog)`
  - Replace `std.net.Server.accept()` with `std.posix.accept(sock, ...)`
  - Replace `stream.writeAll()` with `std.posix.send()` or write via fd
  - Replace `stream.close()` with `std.posix.close(fd)`
  - Keep the same public API: `TcpServer.init()`, `TcpServer.deinit()`, `TcpServer.acceptAndServe()`, `TcpServer.run()`
  - The TcpServer struct should store `socket: std.posix.socket_t` instead of `socket: std.net.Server`
  - Set socket to non-blocking mode via `fcntl(F.SETFL, O.NONBLOCK)` for poll() integration
  - Remove `serveConnection` taking `std.net.Stream` — rewrite to work with raw fd from accept()
  - Expose the listening socket fd for main.zig event loop: store as `self.socket` of type `socket_t`
  - Update error handling: map `std.posix` error sets appropriately
  - Keep all existing logging calls and behavior

  **Must NOT do**:
  - Do not use `std.Io.net` high-level API (requires Io runtime)
  - Do not change the public interface (init/deinit/acceptAndServe signatures beyond type changes)
  - Do not add async or threading
  - Do not remove logging

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Full file rewrite requiring understanding of POSIX socket API and Zig 0.16 std.posix
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser work

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4, 6, 12)
  - **Blocks**: Task 5 (main.zig event loop needs tcp.socket as socket_t)
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `src/servers/tcp.zig:1-178` — Current TCP server implementation (full file — needs complete rewrite)
  - `src/servers/udp.zig:39-75` — UDP server already uses `std.posix.socket()`, `setsockopt()`, `bind()`, `fcntl()` — COPY THIS PATTERN for TCP

  **API/Type References**:
  - `~/.zvm/master/lib/std/posix.zig` — `socket()`, `bind()`, `listen()`, `accept()`, `send()`, `close()`, `setsockopt()`, `fcntl()` function signatures
  - `src/servers/udp.zig:40-60` — Working example of posix socket creation, setsockopt, bind, fcntl in this same project
  - `src/quote_store.zig:QuoteStore` — The store interface (`.isEmpty()`, `.get()`, `.count()`)
  - `src/selector.zig:Selector` — The selector interface (`.next()` returns `!usize`)

  **External References**:
  - Zig 0.16 `std.posix` at `~/.zvm/master/lib/std/posix.zig` — authoritative API reference

  **Acceptance Criteria**:
  - [ ] `tcp.zig` compiles with zero errors
  - [ ] No references to `std.net` remain in tcp.zig
  - [ ] TcpServer.socket is of type `std.posix.socket_t`
  - [ ] TCP server binds, listens, accepts, sends quote, closes connection
  - [ ] Unit tests in tcp.zig pass

  **QA Scenarios:**
  ```
  Scenario: TCP server compiles with new posix API
    Tool: Bash
    Preconditions: tcp.zig rewritten
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Check no errors mentioning tcp.zig or std.net
    Expected Result: tcp.zig compiles cleanly
    Failure Indicators: 'error:' with tcp.zig in path
    Evidence: .sisyphus/evidence/task-3-tcp-compiles.txt

  Scenario: TCP server unit tests pass
    Tool: Bash
    Preconditions: tcp.zig rewritten
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      2. Check tcp server tests pass
    Expected Result: 'tcp server initialization' and 'tcp serve connection with empty store' tests pass
    Failure Indicators: 'FAIL' for tcp tests
    Evidence: .sisyphus/evidence/task-3-tcp-tests.txt
  ```

  **Commit**: YES
  - Message: `refactor(tcp): rewrite TCP server for Zig 0.16 posix socket API`
  - Files: `src/servers/tcp.zig`
  - Pre-commit: `zig build test`

---

- [x] 4. Rewrite UDP Server for Zig 0.16 std.posix Socket API

  **What to do**:
  - Update `src/servers/udp.zig` to remove all `std.net.Address` references
  - The UDP server already uses `std.posix.socket()`, `setsockopt()`, `bind()`, `fcntl()` for the socket itself — good
  - But it still uses `std.net.Address` for address parsing (line 9, 29): replace with manual `sockaddr.in` construction
  - Replace `std.net.Address.parseIp(host, port)` with:
    - Parse host IP string into 4 bytes (handle "0.0.0.0" and "127.0.0.1" etc.)
    - Construct `std.posix.sockaddr.in{ .family = AF.INET, .port = std.mem.nativeToBig(u16, port), .addr = parsed_bytes }`
  - Replace `address.any.family` with direct family from constructed sockaddr
  - Replace `address.getOsSockLen()` with `@sizeOf(std.posix.sockaddr.in)`
  - Update `client_addr` in `receiveAndRespond()` to use `std.posix.sockaddr.storage` for safety (supports IPv6)
  - Replace `address.getPort()` in tests with direct port access from sockaddr
  - Keep all existing behavior: non-blocking mode, REUSEADDR, datagram truncation, logging

  **Must NOT do**:
  - Do not use `std.Io.net` high-level API
  - Do not change UDP protocol behavior (RFC 865 compliance)
  - Do not remove logging

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Requires understanding sockaddr construction and POSIX networking in Zig 0.16
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 6, 12)
  - **Blocks**: Task 5 (main.zig event loop needs udp.socket)
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `src/servers/udp.zig:1-226` — Current UDP server (full file — partially uses posix already, needs address parsing fix)
  - `src/servers/udp.zig:39-60` — Existing posix socket creation pattern (keep this, only fix address parts)

  **API/Type References**:
  - `~/.zvm/master/lib/std/posix.zig` — `sockaddr.in`, `sockaddr.storage`, `AF.INET`, socket API
  - `src/servers/udp.zig:87-88` — Current `sockaddr` usage in recvfrom — change to `sockaddr.storage`

  **Test References**:
  - `src/servers/udp.zig:188-226` — Existing UDP unit tests (need address assertion fix)

  **Acceptance Criteria**:
  - [ ] No references to `std.net` remain in udp.zig
  - [ ] UDP server compiles cleanly
  - [ ] `receiveAndRespond()` uses `sockaddr.storage` for client address
  - [ ] Unit tests pass

  **QA Scenarios:**
  ```
  Scenario: UDP server compiles without std.net references
    Tool: Bash
    Preconditions: udp.zig updated
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Run: grep -n 'std.net' src/servers/udp.zig
    Expected Result: Build passes udp.zig, grep returns no matches
    Failure Indicators: 'error:' mentioning udp.zig or grep finding std.net
    Evidence: .sisyphus/evidence/task-4-udp-compiles.txt

  Scenario: UDP unit tests pass
    Tool: Bash
    Preconditions: udp.zig updated
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      2. Check udp tests pass
    Expected Result: UDP initialization and empty store tests pass
    Failure Indicators: 'FAIL' for udp tests
    Evidence: .sisyphus/evidence/task-4-udp-tests.txt
  ```

  **Commit**: YES
  - Message: `refactor(udp): remove std.net dependency, use posix sockaddr directly`
  - Files: `src/servers/udp.zig`
  - Pre-commit: `zig build test`


---

- [x] 5. Fix main.zig — Event Loop FD References, Selector `try`, FileWatcher Placeholder

  **What to do**:
  - Fix `tcp.socket.stream.handle` reference on lines 172 and 179 — after T3 rewrites tcp.zig, `TcpServer.socket` will be of type `std.posix.socket_t` (an `i32` fd). Change `tcp.socket.stream.handle` to `tcp.socket` (direct fd access)
  - Fix `udp.socket` reference — verify it remains `std.posix.socket_t` after T4 (it already is, but confirm)
  - Add `try` keyword to `selector.Selector.init()` call on line 61 — currently `var sel = selector.Selector.init(...)` but `init()` returns `!Selector` (error union), so it must be `var sel = try selector.Selector.init(...)`
  - Fix line 62: `defer sel.deinit()` — `sel` is a value, but `deinit` takes `*Selector`. This is fine since Zig auto-references for method calls, but verify it compiles
  - Add a `// TODO: Phase 8 - FileWatcher integration` comment placeholder (already exists at line 114) — leave it for T11 to fill in
  - Verify the full event loop compiles and all poll_fds references use correct fd types
  - Verify signal handler setup compiles (sigaction, SIG.TERM, SIG.INT, empty_sigset)
  - Run `zig build` to confirm main.zig compiles end-to-end

  **Must NOT do**:
  - Do not implement FileWatcher integration (that's T11)
  - Do not change configuration loading or quote store initialization
  - Do not add new dependencies or change the event loop architecture
  - Do not modify signal handling beyond what's needed to compile

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Requires understanding how tcp/udp server struct changes from T3/T4 affect main.zig FD references, plus error union handling
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential)
  - **Parallel Group**: Wave 2 (solo)
  - **Blocks**: T7, T8, T9, T10, T11, T13 (all tests and FileWatcher depend on main.zig compiling)
  - **Blocked By**: T1 (selector fix), T3 (tcp rewrite — changes socket type), T4 (udp rewrite — changes address type)

  **References**:

  **Pattern References**:
  - `src/main.zig:170-234` — `runEventLoop()` function with poll_fds setup — lines 172, 179 reference `tcp.socket.stream.handle` which won't exist after T3 rewrite
  - `src/main.zig:61` — `var sel = selector.Selector.init(...)` missing `try` keyword
  - `src/main.zig:72-88` — TCP server initialization (will receive `socket_t` after T3)
  - `src/main.zig:91-106` — UDP server initialization (verify socket type after T4)
  - `src/main.zig:114` — FileWatcher TODO placeholder (leave for T11)

  **API/Type References**:
  - After T3: `TcpServer.socket` will be `std.posix.socket_t` — use directly as fd
  - After T4: `UdpServer.socket` remains `std.posix.socket_t` — use directly as fd
  - `src/selector.zig:46` — `pub fn init(...) !Selector` — returns error union, requires `try`

  **Acceptance Criteria**:
  - [ ] `zig build 2>&1` compiles with zero errors
  - [ ] No references to `tcp.socket.stream.handle` remain
  - [ ] `selector.Selector.init()` call uses `try` keyword
  - [ ] poll_fds uses `tcp.socket` and `udp.socket` directly (both `socket_t`)

  **QA Scenarios:**
  ```
  Scenario: main.zig compiles cleanly after tcp/udp/selector fixes
    Tool: Bash
    Preconditions: T1, T3, T4 completed. selector.zig, tcp.zig, udp.zig already fixed.
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Verify output contains no 'error:' lines
      3. Run: grep -n 'stream.handle' src/main.zig
    Expected Result: Build succeeds. grep returns no matches.
    Failure Indicators: 'error:', 'no member named', 'stream.handle' found in grep
    Evidence: .sisyphus/evidence/task-5-main-compiles.txt

  Scenario: main.zig unit tests pass (if any)
    Tool: Bash
    Preconditions: main.zig changes applied
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      2. Check for compilation errors in main.zig
    Expected Result: No main.zig-related errors
    Failure Indicators: 'error:' mentioning main.zig
    Evidence: .sisyphus/evidence/task-5-main-tests.txt
  ```

  **Commit**: YES
  - Message: `fix(main): update event loop for new server socket types, add try on selector init`
  - Files: `src/main.zig`
  - Pre-commit: `zig build`

---

- [x] 6. Create IDEAS.md — Future Feature Roadmap

  **What to do**:
  - Create `IDEAS.md` in project root with future feature ideas documented
  - Include these sections (from user request):
    - **Backoffice Control Interface**: Web UI on port 80 with simple login, to enable features, update quotes, connect to quote services, enable special modes
    - **Quote Categorization & Tagging**: Tag quotes with categories (inspirational, humorous, historical, etc.)
    - **Holiday/Event-Aware Serving**: Serve contextual quotes during holidays, cultural events, awareness months (e.g., Black History Month, Christmas, International Women's Day)
    - **Quote Service Connectors**: Connect to external quote APIs to pull in fresh content
    - **Special Modes**: Modes like "daily quote", "themed day", "event mode" managed via backoffice
  - Use clear markdown with feature title, description, potential implementation notes
  - Keep it concise — this is an ideas file, not a spec
  - Note that all features would be managed through the backoffice interface

  **Must NOT do**:
  - Do not implement any features — this is documentation only
  - Do not create spec files or detailed technical designs
  - Do not add offensive or insensitive language — keep cultural references respectful and inclusive

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Pure documentation task, no code changes
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 4, 12)
  - **Blocks**: None
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `README.md` — Project overview and current feature list for context on what exists today
  - `specs/001-qotd-nanoservice/spec.md` — Current spec to understand project scope

  **External References**:
  - User's exact words: "Backoffice control interface on port 80 with a simple login to enable features, update quotes, connect to quote services, enable special modes. Also quote categorization, tagging... so as to only give black people quotes during black people month, or on particular holidays, all managed by the backoffice interface"

  **Acceptance Criteria**:
  - [ ] `IDEAS.md` exists in project root
  - [ ] Contains backoffice control interface section
  - [ ] Contains quote categorization/tagging section
  - [ ] Contains holiday/event-aware serving section
  - [ ] Contains quote service connectors section
  - [ ] File is valid markdown (no broken formatting)

  **QA Scenarios:**
  ```
  Scenario: IDEAS.md exists with required sections
    Tool: Bash
    Preconditions: File created
    Steps:
      1. Run: test -f IDEAS.md && echo "EXISTS" || echo "MISSING"
      2. Run: grep -c '## ' IDEAS.md
      3. Run: grep -ci 'backoffice\|categoriz\|tag\|holiday' IDEAS.md
    Expected Result: File exists. At least 4 section headers. At least 4 keyword matches.
    Failure Indicators: File missing, fewer than 4 sections, missing keywords
    Evidence: .sisyphus/evidence/task-6-ideas-md.txt
  ```

  **Commit**: YES
  - Message: `docs: create IDEAS.md with future feature roadmap`
  - Files: `IDEAS.md`
  - Pre-commit: none

---

- [x] 7. Fix end_to_end_test.zig — Remove Old Imports, Fix Unused Constants, Update Address Assertions

  **What to do**:
  - Lines 152-153: Remove `@import("../../src/quote_store.zig")` and `@import("../../src/selector.zig")` — these are outside the module path. Replace with `src.quote_store_mod` and `src.selector_mod` (already used elsewhere in this file)
  - Lines 159, 161: `store.add("Quote 1")` etc. — these depend on T2 adding the `add()` method to QuoteStore. After T2, these should compile
  - Fix unused local constants: the test "selection mode integration across servers" at line 149 uses `@import` style that was fixed, but also check for any `const` that's assigned but never used (Zig treats unused locals as compile errors)
  - Lines 69-70, 145-146: `tcp.address.getPort()` and `udp.address.getPort()` — after T3/T4 rewrite, servers won't have `.address` field with `.getPort()` method. These need to be updated to match the new server API (likely `tcp.port` or similar direct field)
  - Verify the `sel.next()` calls match the updated Selector API — currently `sel.next()` returns `?usize` and some tests use it without `try`, which is correct since `next()` returns optional not error union
  - Run `zig build test-all` after changes to verify

  **Must NOT do**:
  - Do not change test logic or assertions beyond what's needed to compile
  - Do not add new tests (that's separate work if needed)
  - Do not change the `src` module import pattern (it's correct)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward import fixes and field name updates
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 8, 9, 13)
  - **Blocks**: T15 (full test suite run)
  - **Blocked By**: T2 (store.add method), T3 (tcp server API change), T4 (udp server API change), T5 (main.zig compiles)

  **References**:

  **Pattern References**:
  - `tests/integration/end_to_end_test.zig:1-81` — Tests using `src` module imports (correct pattern)
  - `tests/integration/end_to_end_test.zig:149-177` — "selection mode integration" test using old `@import("../../src/...")` pattern (needs fix)
  - `tests/integration/end_to_end_test.zig:69-70` — `tcp.address.getPort()` / `udp.address.getPort()` assertions (need update after T3/T4)

  **API/Type References**:
  - After T3: TcpServer struct fields — check what field exposes the port (likely `self.port` stored during init)
  - After T4: UdpServer struct fields — same check
  - `src/quote_store.zig` after T2: `store.add(content)` method available

  **Acceptance Criteria**:
  - [ ] No `@import("../../src/")` paths remain in the file
  - [ ] No unused local constant errors
  - [ ] All port assertions match new server API
  - [ ] `zig build test-all 2>&1` — end_to_end tests pass

  **QA Scenarios:**
  ```
  Scenario: end_to_end_test.zig compiles and passes
    Tool: Bash
    Preconditions: T2, T3, T4, T5 completed
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test-all 2>&1
      2. Check for end_to_end test results
      3. Run: grep -n '@import("../../' tests/integration/end_to_end_test.zig
    Expected Result: Tests pass, no old import paths found
    Failure Indicators: 'FAIL', 'error:', old imports found
    Evidence: .sisyphus/evidence/task-7-e2e-tests.txt
  ```

  **Commit**: YES (groups with T8, T9, T13)
  - Message: `fix(tests): update integration tests for Zig 0.16 API changes`
  - Files: `tests/integration/end_to_end_test.zig`
  - Pre-commit: `zig build test-all`

---

- [x] 8. Fix protocol_test.zig — Update store.add() Calls and Server Address Assertions

  **What to do**:
  - Verify `store.add()` calls in `createTestStore()` (lines 18-20) compile after T2 adds the method
  - Lines 119, 225, 242, 261: `store.add(long_quote)` — same verification
  - Lines 42, 85, 158-159, 187-188: `server.address.getPort()` assertions — after T3/T4 rewrite, servers won't have `.address` field. Update to match new API (e.g., `server.port`)
  - Line 202, 206, 210, 214: `sel.next()` returns `?usize`, but tests at line 202+ use `try sel.next()` which expects error union — check if this matches the actual `next()` signature. If `next()` returns `?usize` (no error), remove `try`. If it returns `!?usize`, keep `try`.
  - Verify all `try testing.expect(...)` and `try testing.expectEqual(...)` patterns are correct for Zig 0.16
  - Run `zig build test-all` after changes

  **Must NOT do**:
  - Do not change test assertions or expected values
  - Do not add new test cases
  - Do not modify the `src` module import pattern

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Method name and field access updates only
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 9, 13)
  - **Blocks**: T14 (binary verification), T15 (full test suite)
  - **Blocked By**: T2 (store.add method), T3 (tcp API), T4 (udp API), T5 (main.zig compiles)

  **References**:

  **Pattern References**:
  - `tests/integration/protocol_test.zig:14-23` — `createTestStore()` using `store.add()` calls
  - `tests/integration/protocol_test.zig:42,85,158-159,187-188` — `server.address.getPort()` assertions needing update
  - `tests/integration/protocol_test.zig:191-216` — "Selection modes work" test with `try sel.next()` calls

  **API/Type References**:
  - `src/selector.zig:120` — `pub fn next(self: *Selector) ?usize` — returns optional, NOT error union
  - After T3: TcpServer port access pattern
  - After T4: UdpServer port access pattern

  **Acceptance Criteria**:
  - [ ] `createTestStore()` compiles with `store.add()` calls
  - [ ] All `server.address.getPort()` updated to new API
  - [ ] `sel.next()` calls match actual return type (?usize)
  - [ ] `zig build test-all 2>&1` — protocol tests pass

  **QA Scenarios:**
  ```
  Scenario: protocol_test.zig compiles and all tests pass
    Tool: Bash
    Preconditions: T2, T3, T4, T5 completed
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test-all 2>&1
      2. Look for protocol_test results (RFC 865 compliance tests)
    Expected Result: All 10 protocol tests pass
    Failure Indicators: 'FAIL', 'error:', 'no member named'
    Evidence: .sisyphus/evidence/task-8-protocol-tests.txt
  ```

  **Commit**: YES (groups with T7, T9, T13)
  - Message: `fix(tests): update protocol_test.zig for Zig 0.16 API changes`
  - Files: `tests/integration/protocol_test.zig`
  - Pre-commit: `zig build test-all`

---

- [ ] 9. Fix perf_test.zig — Remove std.net, Fix addQuote(), Fix nanoTimestamp/Timer

  **What to do**:
  - Line 3: `const net = std.net;` — REMOVE this entirely. `std.net` doesn't exist in Zig 0.16
  - Lines 50-51, 102-104: Replace `net.Address.parseIp("127.0.0.1", port)` with manual `std.posix.sockaddr.in` construction:
    ```
    const server_addr = std.posix.sockaddr.in{
      .family = std.posix.AF.INET,
      .port = std.mem.nativeToBig(u16, port),
      .addr = .{ 127, 0, 0, 1 },  // or equivalent packed u32
    };
    ```
  - Lines 52, 61: `client_addr.any.family` → `@intFromEnum(server_addr.family)`, `client_addr.getOsSockLen()` → `@sizeOf(std.posix.sockaddr.in)`
  - Lines 32, 92, 161, 187: `store.addQuote(...)` — depends on T2 adding the `addQuote()` alias. After T2, these should compile
  - Line 151: `std.time.Timer.start()` — verify this exists in Zig 0.16. If not, use `std.time.Instant.now()` instead and compute elapsed manually
  - Lines 47, 70, 119, 133, 195, 203: `std.time.nanoTimestamp()` — verify this exists in Zig 0.16. If removed, use `std.time.Instant.now()` and compute nanoseconds from `.timestamp.sec` and `.timestamp.nsec`
  - Lines 39, 99: `server.listen()` — after T3/T4 rewrite, servers may not have a separate `listen()` method (init may do everything). Check post-T3/T4 API and adjust
  - Line 64: `server.acceptOne()` — may not exist after T3 rewrite. Check post-T3 TcpServer API for equivalent
  - Line 125: `server.handleOne()` — may not exist after T4 rewrite. Check post-T4 UdpServer API for equivalent
  - Line 198: `sel.next(store.count())` — `next()` takes no arguments (only `self`). Fix to `sel.next()`
  - Run `zig build test-all` after changes

  **Must NOT do**:
  - Do not change performance thresholds (10ms TCP, 10ms UDP, 5s for 10k quotes)
  - Do not remove any perf tests
  - Do not add external dependencies

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: API migration fixes, though touches many lines. All changes are mechanical replacements
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 8, 13)
  - **Blocks**: T14 (binary verification), T15 (full test suite)
  - **Blocked By**: T2 (addQuote method), T3 (tcp API changes — listen/acceptOne), T4 (udp API changes — handleOne), T5 (main.zig compiles)

  **References**:

  **Pattern References**:
  - `tests/integration/perf_test.zig:1-211` — Full file (needs multiple fixes throughout)
  - `src/servers/tcp.zig` (post-T3) — Check for `listen()`, `acceptOne()` equivalents
  - `src/servers/udp.zig` (post-T4) — Check for `listen()`, `handleOne()` equivalents

  **API/Type References**:
  - `std.posix.sockaddr.in` — Replacement for `std.net.Address.parseIp()`
  - `std.time.Instant` — Potential replacement for `nanoTimestamp()` and `Timer`
  - `src/selector.zig:120` — `next()` takes no args (fix line 198)

  **Acceptance Criteria**:
  - [ ] No references to `std.net` remain in perf_test.zig
  - [ ] `store.addQuote()` calls compile (after T2)
  - [ ] Timer/timestamp APIs work with Zig 0.16
  - [ ] `sel.next()` called without arguments
  - [ ] `zig build test-all 2>&1` — perf tests pass

  **QA Scenarios:**
  ```
  Scenario: perf_test.zig compiles and passes
    Tool: Bash
    Preconditions: T2, T3, T4, T5 completed
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test-all 2>&1
      2. Check for perf test results (TCP <10ms, UDP <10ms, 10k quotes <5s)
      3. Run: grep -n 'std.net' tests/integration/perf_test.zig
    Expected Result: All perf tests pass, no std.net references
    Failure Indicators: 'FAIL', 'error:', std.net found in grep
    Evidence: .sisyphus/evidence/task-9-perf-tests.txt

  Scenario: Performance thresholds met
    Tool: Bash
    Preconditions: All perf tests pass
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test-all 2>&1 | grep '\[PERF\]'
    Expected Result: TCP avg <10ms, UDP avg <10ms, 10k quotes loaded in <5s
    Failure Indicators: avg times exceeding thresholds
    Evidence: .sisyphus/evidence/task-9-perf-thresholds.txt
  ```

  **Commit**: YES (groups with T7, T8, T13)
  - Message: `fix(tests): update perf_test.zig for Zig 0.16 API changes`
  - Files: `tests/integration/perf_test.zig`
  - Pre-commit: `zig build test-all`

---

- [x] 10. Implement FileWatcher in src/watcher.zig — Polling-Based Hot Reload

  **What to do**:
  - Create new file `src/watcher.zig` implementing a polling-based FileWatcher
  - The FileWatcher should:
    - Accept a list of directory paths and a poll interval (from config)
    - Track last-modified timestamps for each watched directory
    - Provide a `check() !bool` method that returns `true` if any directory's contents changed since last check
    - Provide a `init(allocator, directories, interval_seconds)` and `deinit()` lifecycle
  - Implementation approach: use `std.fs.cwd().statFile()` or `std.fs.Dir.stat()` to check directory modification times
  - Alternative simpler approach: store a hash of directory listing (filenames + sizes) and compare on each check
  - The FileWatcher should NOT do the actual reloading — it only detects changes. main.zig (T11) will call `store.build()` and `sel.reset()` when changes detected
  - Keep it minimal — this is a nanoservice, not a file watcher framework
  - Add unit tests for FileWatcher (at least: init/deinit, no-change detection, simulated change detection)

  **Must NOT do**:
  - Do not use inotify/kqueue/FSEvents — polling only (cross-platform, simple)
  - Do not implement the reload logic (that's T11)
  - Do not add external dependencies
  - Do not over-engineer — simple polling with stat() is fine

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: New module from scratch requiring understanding of Zig 0.16 filesystem API
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: NO (needs main.zig compiling first)
  - **Parallel Group**: Wave 4 (with T11, T14, T15)
  - **Blocks**: T11 (FileWatcher integration into main.zig)
  - **Blocked By**: T5 (main.zig compiles — need the project buildable before adding new modules)

  **References**:

  **Pattern References**:
  - `src/quote_store.zig:140-159` — Directory walking pattern using `std.fs.cwd().openDir()` and `dir.walk()`
  - `src/config.zig` — Configuration struct with `polling_interval` field and `directories` list
  - `src/logger.zig` — Logger pattern for structured logging
  - `README.md:12` — "Hot Reload: Polls directories for changes and reloads without restart" — confirms polling approach

  **API/Type References**:
  - `std.fs.Dir.stat()` — Returns `Stat` with `.mtime` field for last-modified check
  - `std.fs.cwd().statFile(path)` — Stat a file directly
  - `src/config.zig:Configuration` — `.directories` ([]const []const u8) and `.polling_interval` (u64 seconds)

  **Acceptance Criteria**:
  - [ ] `src/watcher.zig` exists with `FileWatcher` struct
  - [ ] `init()`, `deinit()`, `check()` methods present
  - [ ] `zig build 2>&1` compiles without errors (watcher included in build)
  - [ ] `zig build test 2>&1` — watcher unit tests pass

  **QA Scenarios:**
  ```
  Scenario: FileWatcher compiles and unit tests pass
    Tool: Bash
    Preconditions: src/watcher.zig created, build.zig includes it
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      3. Check for watcher-related test results
    Expected Result: Compiles cleanly, watcher tests pass
    Failure Indicators: 'error:', 'FAIL' for watcher tests
    Evidence: .sisyphus/evidence/task-10-watcher-compiles.txt

  Scenario: FileWatcher detects no change when nothing changed
    Tool: Bash
    Preconditions: FileWatcher unit tests include no-change scenario
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1 | grep -i 'watcher'
    Expected Result: No-change test passes (check() returns false)
    Failure Indicators: Assertion failure on no-change test
    Evidence: .sisyphus/evidence/task-10-watcher-no-change.txt
  ```

  **Commit**: YES
  - Message: `feat(watcher): implement FileWatcher for polling-based hot reload`
  - Files: `src/watcher.zig`
  - Pre-commit: `zig build test`

---

- [x] 11. Integrate FileWatcher into main.zig Event Loop

  **What to do**:
  - Import `watcher.zig` in main.zig: `const watcher = @import("watcher.zig");`
  - Add `pub const watcher_mod = watcher;` to module exports
  - After quote store initialization (around line 51), create FileWatcher:
    ```zig
    var file_watcher = watcher.FileWatcher.init(allocator, cfg.directories, cfg.polling_interval);
    defer file_watcher.deinit();
    ```
  - Replace the TODO comment at line 114 with FileWatcher integration
  - In the event loop (`runEventLoop`), add a periodic check: after poll() timeout or between iterations, call `file_watcher.check()`. If it returns `true`:
    - Call `store.build(cfg.directories)` to reload quotes
    - Call `sel.reset(store.count())` to reset selector for new quote count
    - Log the reload event
  - Approach: use the poll() timeout (already 1000ms) as the watcher check interval. On each timeout (ready == 0), check the watcher. The watcher internally tracks its own interval and returns false if not enough time has passed
  - Pass `file_watcher`, `store`, `sel`, and `cfg` to `runEventLoop` (update signature)

  **Must NOT do**:
  - Do not change FileWatcher implementation (that's T10)
  - Do not add threading or async
  - Do not change the poll() architecture

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Event loop modification with multiple component interactions (watcher + store + selector)
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (after T10)
  - **Blocks**: T15 (full test suite)
  - **Blocked By**: T5 (main.zig compiles), T10 (FileWatcher exists)

  **References**:

  **Pattern References**:
  - `src/main.zig:114` — TODO placeholder for FileWatcher integration
  - `src/main.zig:164-234` — `runEventLoop()` function — add watcher check after poll timeout
  - `src/main.zig:44-50` — `store.build()` call pattern for reloading quotes
  - `src/selector.zig:205-240` — `selector.reset(new_count)` method for resetting after reload

  **API/Type References**:
  - After T10: `watcher.FileWatcher.init(allocator, dirs, interval)`, `.check() !bool`, `.deinit()`
  - `src/quote_store.zig:93` — `store.build(directories)` for reload
  - `src/selector.zig:205` — `sel.reset(new_quote_count)` for post-reload reset

  **Acceptance Criteria**:
  - [ ] FileWatcher imported and initialized in main.zig
  - [ ] TODO comment at line 114 replaced with actual integration
  - [ ] Event loop checks watcher on poll timeout
  - [ ] Reload triggers `store.build()` + `sel.reset()`
  - [ ] `zig build 2>&1` compiles without errors

  **QA Scenarios:**
  ```
  Scenario: main.zig compiles with FileWatcher integration
    Tool: Bash
    Preconditions: T10 completed (watcher.zig exists)
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build 2>&1
      2. Run: grep -n 'watcher' src/main.zig
    Expected Result: Compiles cleanly, watcher references found in main.zig
    Failure Indicators: 'error:', no watcher references
    Evidence: .sisyphus/evidence/task-11-watcher-integration.txt

  Scenario: Hot reload works with file changes
    Tool: Bash
    Preconditions: Binary built, test quotes directory exists
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build
      2. Start server in background: ./zig-out/bin/quotez &
      3. Wait 2 seconds: sleep 2
      4. Add a new quote file: echo 'Hot reload test quote' > tests/fixtures/quotes/hot_reload_test.txt
      5. Wait for poll interval + 2 seconds: sleep 62
      6. Connect and get quote: echo '' | nc -q1 localhost 8017
      7. Clean up: kill %1; rm tests/fixtures/quotes/hot_reload_test.txt
    Expected Result: Server starts, doesn't crash. New quote file is picked up after reload.
    Failure Indicators: Server crash, segfault, reload error in logs
    Evidence: .sisyphus/evidence/task-11-hot-reload-test.txt
  ```

  **Commit**: YES
  - Message: `feat(main): integrate FileWatcher into event loop for hot reload`
  - Files: `src/main.zig`
  - Pre-commit: `zig build`

---

- [x] 12. Update README.md and Spec Documents to Zig 0.16.0

  **What to do**:
  - `README.md` line 23: Change "Zig 0.13.0 or later" to "Zig 0.16.0 or later"
  - `README.md`: Update development status section to reflect completed migration
  - `AGENTS.md`: Already says Zig 0.16.0 — verify and leave as-is
  - `specs/001-qotd-nanoservice/spec.md`: Find any Zig version references and update to 0.16.0
  - `specs/001-qotd-nanoservice/plan.md`: Update Zig version references
  - `specs/001-qotd-nanoservice/tasks.md`: Update task status to reflect migration progress
  - Ensure Dockerfile build instructions reference correct Zig version

  **Must NOT do**:
  - Do not change project architecture descriptions
  - Do not add new sections to README
  - Do not modify code files

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Pure documentation updates, no code changes
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 4, 6)
  - **Blocks**: None
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `README.md:23` — "Zig 0.13.0 or later" → needs update
  - `AGENTS.md:6` — Already says "Zig 0.16.0" — verify
  - `specs/001-qotd-nanoservice/spec.md` — Check for Zig version refs
  - `specs/001-qotd-nanoservice/plan.md` — Check for Zig version refs
  - `specs/001-qotd-nanoservice/tasks.md` — Update task completion status

  **Acceptance Criteria**:
  - [ ] README.md says "Zig 0.16.0" not "0.13"
  - [ ] No spec docs reference "0.13"
  - [ ] Task status reflects current migration progress

  **QA Scenarios:**
  ```
  Scenario: No Zig 0.13 references remain in docs
    Tool: Bash
    Preconditions: All doc files updated
    Steps:
      1. Run: grep -rn '0\.13' README.md AGENTS.md specs/
    Expected Result: No matches (all updated to 0.16)
    Failure Indicators: Any file still referencing 0.13
    Evidence: .sisyphus/evidence/task-12-docs-updated.txt
  ```

  **Commit**: YES
  - Message: `docs: update README and specs to Zig 0.16.0`
  - Files: `README.md`, `specs/001-qotd-nanoservice/spec.md`, `specs/001-qotd-nanoservice/plan.md`, `specs/001-qotd-nanoservice/tasks.md`
  - Pre-commit: none

---

- [x] 13. Verify Selector Tests Pass (Post-Migration)

  **What to do**:
  - There is no separate `tests/integration/selector_test.zig` — selector tests are embedded in `src/selector.zig` (lines 244-368)
  - After T1 fixes `initWithSeed` and the `errdefer` bug, verify all 8 selector unit tests pass:
    1. `sequential mode basic operation`
    2. `sequential mode with single quote`
    3. `random mode returns valid indices`
    4. `random-no-repeat exhaustion and reset`
    5. `shuffle-cycle full cycle uniqueness`
    6. `shuffle-cycle reshuffle on exhaustion`
    7. `selector reset`
    8. `empty quote store handling`
  - If any test fails, investigate and fix the specific issue in selector.zig
  - Check that `std.time.Instant.now()` with `.timestamp.sec` / `.timestamp.nsec` works correctly for seed generation
  - Verify no memory leaks (test allocator will report these)

  **Must NOT do**:
  - Do not change the Selector public API
  - Do not change test expectations (they define correct behavior)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Verification task — run tests, check results, maybe minor fixes
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 8, 9)
  - **Blocks**: T15 (full test suite)
  - **Blocked By**: T1 (selector fix), T5 (main.zig compiles)

  **References**:

  **Pattern References**:
  - `src/selector.zig:244-368` — All 8 unit tests embedded in selector.zig
  - `src/selector.zig:46-104` — `init()` function (post-T1 fix)

  **Acceptance Criteria**:
  - [ ] `zig build test 2>&1` — all 8 selector tests pass
  - [ ] No memory leaks reported
  - [ ] No `initWithSeed` errors

  **QA Scenarios:**
  ```
  Scenario: All 8 selector tests pass
    Tool: Bash
    Preconditions: T1 completed (initWithSeed fixed)
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test 2>&1
      2. Count passing selector tests
    Expected Result: All 8 selector tests pass, zero failures
    Failure Indicators: 'FAIL', 'error:', memory leak warnings
    Evidence: .sisyphus/evidence/task-13-selector-tests.txt
  ```

  **Commit**: YES (groups with T7, T8, T9 if fixes needed)
  - Message: `fix(selector): verify and fix selector tests for Zig 0.16`
  - Files: `src/selector.zig` (only if fixes needed)
  - Pre-commit: `zig build test`

---

- [x] 14. Verify Static Binary Build + Size < 5MB

  **What to do**:
  - Build a release-optimized static binary: `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl`
  - Verify the build succeeds without errors
  - Check binary size: `ls -la zig-out/bin/quotez` — must be < 5MB (5,242,880 bytes)
  - Verify the binary is statically linked: `file zig-out/bin/quotez` should show "statically linked"
  - Verify the binary is a valid ELF executable for x86_64-linux
  - Optionally run `strip` if size is close to limit (but Zig's ReleaseSmall should be well under)

  **Must NOT do**:
  - Do not modify source code in this task
  - Do not change build.zig optimization settings

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single build command + verification checks
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with T10, T11, T15)
  - **Blocks**: T16 (Docker build needs the static binary)
  - **Blocked By**: T8, T9 (all code must compile cleanly first)

  **References**:

  **Pattern References**:
  - `build.zig` — Build configuration supporting `-Doptimize=ReleaseSmall` and `-Dtarget=x86_64-linux-musl`
  - `Dockerfile:4` — Build command reference: `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl`

  **Acceptance Criteria**:
  - [ ] `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl` succeeds
  - [ ] `ls -la zig-out/bin/quotez` shows file size < 5,242,880 bytes
  - [ ] `file zig-out/bin/quotez` shows "statically linked" and "x86-64"

  **QA Scenarios:**
  ```
  Scenario: Static binary builds and meets size constraint
    Tool: Bash
    Preconditions: All source code compiles (T1-T9 completed)
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl 2>&1
      2. Run: ls -la zig-out/bin/quotez
      3. Run: file zig-out/bin/quotez
      4. Run: stat --format='%s' zig-out/bin/quotez
    Expected Result: Build succeeds, binary < 5MB, statically linked x86-64 ELF
    Failure Indicators: Build error, size > 5242880, not statically linked
    Evidence: .sisyphus/evidence/task-14-static-binary.txt
  ```

  **Commit**: NO (verification only, no code changes)

---

- [x] 15. Run Full Test Suite — zig build test-all (PARTIAL: blocked by T9 perf_test.zig)

  **What to do**:
  - Run the complete test suite: `zig build test-all`
  - This runs unit tests + integration tests + e2e tests + perf tests
  - Verify ALL tests pass with zero failures
  - If any tests fail, investigate and fix (may require going back to earlier tasks)
  - Capture full test output as evidence
  - Count total tests passed vs failed

  **Must NOT do**:
  - Do not skip failing tests with `error.SkipZigTest` unless they legitimately need port availability
  - Do not change test thresholds to make tests pass

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Run command and verify output, possibly minor fixes
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES (can run alongside T14)
  - **Parallel Group**: Wave 4 (with T10, T11, T14)
  - **Blocks**: T17 (performance verification)
  - **Blocked By**: T7, T8, T9, T13 (all test files must be fixed first)

  **References**:

  **Pattern References**:
  - `build.zig` — `test-all` build step configuration
  - All test files in `tests/integration/` — fixed by T7, T8, T9
  - All test blocks in `src/*.zig` — fixed by T1, T2

  **Acceptance Criteria**:
  - [ ] `zig build test-all 2>&1` exits with code 0
  - [ ] Zero test failures in output
  - [ ] All test categories present: unit, integration, e2e, perf

  **QA Scenarios:**
  ```
  Scenario: Full test suite passes
    Tool: Bash
    Preconditions: All test files fixed (T7, T8, T9, T13)
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test-all 2>&1
      2. Count 'PASS' and 'FAIL' in output
      3. Check exit code: echo $?
    Expected Result: All tests pass, exit code 0
    Failure Indicators: Any 'FAIL', non-zero exit code
    Evidence: .sisyphus/evidence/task-15-full-test-suite.txt
  ```

  **Commit**: NO (verification only, unless fixes needed)

---

- [x] 16. Fix Dockerfile + Docker Config + Build Image

  **What to do**:
  - Fix port mismatch in Dockerfile:
    - `Dockerfile:10` says `-p 8017:8017` in the comment
    - `Dockerfile:26` says `EXPOSE 8017/tcp 8017/udp`
    - `quotez.docker.toml` says `tcp_port = 17` and `udp_port = 17`
    - RFC 865 standard port is 17. Docker should use port 17 inside the container
    - Change Dockerfile `EXPOSE` to `EXPOSE 17/tcp 17/udp`
    - Update Dockerfile run comment to `-p 17:17/tcp -p 17:17/udp`
  - Verify `quotez.docker.toml` has correct paths:
    - `host = "0.0.0.0"` (bind to all interfaces in container)
    - `directories = ["/data/quotes"]`
    - `tcp_port = 17`, `udp_port = 17`
  - Build the Docker image: `docker build -t quotez .`
  - Verify image size < 10MB: `docker images quotez`
  - Test the container runs:
    - `docker run -d --name quotez-test -p 17:17/tcp -p 17:17/udp quotez`
    - `echo '' | nc -q1 localhost 17` (TCP test)
    - `echo '' | nc -u -w1 localhost 17` (UDP test)
    - `docker logs quotez-test` (check for startup logs)
    - `docker rm -f quotez-test` (cleanup)

  **Must NOT do**:
  - Do not set up Docker registry/distribution (user explicitly excluded this)
  - Do not add health checks (scratch container doesn't support shell-based checks)
  - Do not change the scratch base image
  - Do not add runtime dependencies

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small config fixes + Docker build/test commands
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 5
  - **Blocks**: None (final task before verification)
  - **Blocked By**: T14 (static binary must exist for Docker COPY)

  **References**:

  **Pattern References**:
  - `Dockerfile:1-31` — Current Dockerfile with port mismatch
  - `quotez.docker.toml:1-11` — Docker-specific config (port 17, /data/quotes)
  - `quotez.toml` — Local config (port 8017) for reference — Docker uses different port

  **Acceptance Criteria**:
  - [ ] Dockerfile `EXPOSE` says `17/tcp 17/udp`
  - [ ] `docker build -t quotez .` succeeds
  - [ ] `docker images quotez --format '{{.Size}}'` shows < 10MB
  - [ ] Container starts and serves quotes on port 17

  **QA Scenarios:**
  ```
  Scenario: Docker image builds and is under 10MB
    Tool: Bash
    Preconditions: Static binary built (T14)
    Steps:
      1. Run: docker build -t quotez . 2>&1
      2. Run: docker images quotez --format '{{.Repository}}:{{.Tag}} {{.Size}}'
    Expected Result: Build succeeds, image size < 10MB
    Failure Indicators: Build failure, image > 10MB
    Evidence: .sisyphus/evidence/task-16-docker-build.txt

  Scenario: Docker container serves quotes on port 17
    Tool: Bash
    Preconditions: Docker image built
    Steps:
      1. Run: docker run -d --name quotez-test -p 17:17/tcp -p 17:17/udp quotez
      2. Run: sleep 2
      3. Run: echo '' | nc -q1 localhost 17
      4. Run: docker logs quotez-test 2>&1
      5. Run: docker rm -f quotez-test
    Expected Result: Container starts, nc receives a quote string, logs show startup
    Failure Indicators: Container exits immediately, nc gets no response, error in logs
    Evidence: .sisyphus/evidence/task-16-docker-serve.txt
  ```

  **Commit**: YES
  - Message: `fix(docker): align Dockerfile ports with RFC 865 standard, verify image builds`
  - Files: `Dockerfile`
  - Pre-commit: `docker build -t quotez .`

---

- [ ] 17. Performance Benchmarks Verification

  **What to do**:
  - Build the release binary: `zig build -Doptimize=ReleaseFast`
  - Start the server locally and run manual performance checks:
    - TCP: Time 100 sequential connections with `nc` or a simple loop
    - UDP: Time 100 sequential datagrams
  - Verify the server handles rapid connections without crashing or leaking
  - Run the perf tests specifically: `zig build test-all` and filter for PERF output
  - Compare results against thresholds:
    - TCP response: avg < 10ms
    - UDP response: avg < 10ms
    - 10k quote load: < 5 seconds
    - 10k selections: sub-millisecond per selection
  - Document results in evidence file

  **Must NOT do**:
  - Do not change performance thresholds
  - Do not optimize code (this is verification only)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Run benchmarks and capture results
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with T16)
  - **Blocks**: None
  - **Blocked By**: T15 (full test suite must pass first)

  **References**:

  **Pattern References**:
  - `tests/integration/perf_test.zig` — Performance test definitions and thresholds

  **Acceptance Criteria**:
  - [ ] TCP avg response time < 10ms
  - [ ] UDP avg response time < 10ms
  - [ ] 10k quotes load in < 5 seconds
  - [ ] 10k selections in sub-millisecond per selection

  **QA Scenarios:**
  ```
  Scenario: All performance benchmarks pass
    Tool: Bash
    Preconditions: Full test suite passes (T15)
    Steps:
      1. Run: export PATH="$HOME/.zvm/master:$PATH" && zig build test-all 2>&1 | grep '\[PERF\]'
    Expected Result: All PERF lines show values within thresholds
    Failure Indicators: Any threshold exceeded
    Evidence: .sisyphus/evidence/task-17-perf-benchmarks.txt
  ```

  **Commit**: NO (verification only)
## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE. Rejection → fix → re-run.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `zig build` + `zig build test` + `zig build test-all`. Review all changed files for: `as any` equivalent patterns, empty catches, debug prints in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names.
  Output: `Build [PASS/FAIL] | Tests [N pass/N fail] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high`
  Start from clean state. Build binary. Start server. Test TCP with `echo "" | nc localhost 8017`. Test UDP with `echo "" | nc -u localhost 8017`. Verify quote is returned. Test with empty quote directory. Test with multiple quotes and verify selection modes. Run in Docker container. Save evidence to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff (git log/diff). Verify 1:1 — everything in spec was built, nothing beyond spec was built. Check "Must NOT do" compliance. Detect cross-task contamination. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

- **Wave 1**: `fix(selector): implement initWithSeed and fix errdefer memory bug` — src/selector.zig
- **Wave 1**: `feat(store): add QuoteStore.add() and addQuote() helper methods` — src/quote_store.zig
- **Wave 1**: `refactor(tcp): rewrite TCP server for Zig 0.16 posix socket API` — src/servers/tcp.zig
- **Wave 1**: `refactor(udp): rewrite UDP server for Zig 0.16 posix socket API` — src/servers/udp.zig
- **Wave 1**: `docs: create IDEAS.md with future feature roadmap` — IDEAS.md
- **Wave 1**: `docs: update README and specs to Zig 0.16.0` — README.md, specs/
- **Wave 2**: `fix(main): update event loop for new server API, add try on selector init` — src/main.zig
- **Wave 3**: `fix(tests): update integration tests for Zig 0.16 API changes` — tests/integration/
- **Wave 4**: `feat(watcher): implement FileWatcher for hot reload` — src/watcher.zig
- **Wave 4**: `feat(main): integrate FileWatcher into event loop` — src/main.zig
- **Wave 5**: `fix(docker): align Dockerfile ports with config, verify image size` — Dockerfile, quotez.docker.toml

---

## Success Criteria

### Verification Commands
```bash
export PATH="$HOME/.zvm/master:$PATH"
zig build                    # Expected: BUILD SUCCEEDED, zero errors
zig build test               # Expected: All unit tests pass
zig build test-all           # Expected: All tests pass (unit + integration + e2e + perf)
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl  # Expected: Static binary produced
ls -la zig-out/bin/quotez    # Expected: < 5MB
docker build -t quotez .     # Expected: Image builds successfully
docker images quotez         # Expected: < 10MB
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All tests pass
- [ ] Server responds on TCP and UDP
- [ ] Docker container runs correctly
- [ ] IDEAS.md exists with future features
- [ ] README.md says Zig 0.16.0
