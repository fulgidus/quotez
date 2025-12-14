# Tasks: QOTD Nanoservice

**Input**: Design documents from `/specs/001-qotd-nanoservice/`  
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md  
**Feature**: quotez - RFC 865 QOTD protocol implementation in Zig

**Tests**: Tests are embedded within Zig source files using `test` blocks per Zig convention. Integration tests in separate `tests/` directory.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Single project structure at repository root:
- `src/` - Source code modules
- `tests/` - Integration tests
- `build.zig` - Zig build configuration

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic Zig structure

- [X] T001 Create project directory structure with src/, tests/, tests/fixtures/, tests/integration/, tests/unit/ per plan.md
- [X] T002 Initialize Zig project with build.zig targeting x86_64-linux-musl and ReleaseSmall optimization
- [X] T003 [P] Create test fixture directories and sample quote files in tests/fixtures/quotes/ (sample.txt, sample.json, sample.csv, sample.toml, sample.yaml)
- [X] T004 [P] Create .gitignore for Zig artifacts (zig-cache/, zig-out/)
- [X] T005 [P] Setup Dockerfile with FROM scratch base image per contracts/qotd-protocol.md and quickstart.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Implement Configuration entity in src/config.zig with TOML parsing, validation, and defaults per contracts/config-schema.md
- [X] T007 Add unit tests for Configuration in src/config.zig using Zig test blocks (valid/invalid TOML, defaults, validation)
- [X] T008 [P] Implement Logger utility in src/logger.zig with structured stdout logging per research.md logging strategy
- [X] T009 [P] Implement Quote entity structure and Blake3 hashing in src/quote_store.zig per data-model.md Quote entity
- [X] T010 Implement QuoteStore in src/quote_store.zig with quotes array, metadata tracking, and allocator management per data-model.md
- [X] T011 Add unit tests for QuoteStore deduplication logic in src/quote_store.zig using Zig test blocks
- [X] T012 [P] Implement SelectionMode enum and Selector tagged union in src/selector.zig per data-model.md Selector entity
- [X] T013 Implement all four selection mode algorithms (random, sequential, random-no-repeat, shuffle-cycle) in src/selector.zig
- [X] T014 Add unit tests for each Selector mode in src/selector.zig (wraparound, reset behavior, shuffle uniqueness)

**Checkpoint**: Foundation ready - configuration, logging, quote storage, and selection modes are functional

---

## Phase 3: User Story 3 - Load Quotes from Local Files (Priority: P1) 🎯 MVP FOUNDATIONAL

**Goal**: Implement quote loading from 5 file formats with auto-detection, parsing, and deduplication

**Why First**: This is the foundational prerequisite for serving quotes (US1 and US2). Without loaded quotes, TCP/UDP servers have nothing to serve.

**Independent Test**: Place quote files in test directory, run service, verify via logs that all formats parsed and duplicates removed

### Implementation for User Story 3

- [X] T015 [P] [US3] Create parser interface/trait in src/parsers/parser.zig with common parse() signature
- [X] T016 [P] [US3] Implement plaintext parser in src/parsers/txt.zig per contracts/quote-formats.md (split by newlines, trim whitespace)
- [X] T017 [P] [US3] Implement JSON parser in src/parsers/json.zig using std.json.parseFromSlice per contracts/quote-formats.md
- [X] T018 [P] [US3] Implement CSV parser in src/parsers/csv.zig with delimiter detection per contracts/quote-formats.md
- [X] T019 [P] [US3] Implement TOML parser in src/parsers/toml.zig (inline minimal parser or zig-toml) per contracts/quote-formats.md
- [X] T020 [P] [US3] Implement YAML parser in src/parsers/yaml.zig (minimal subset support) per contracts/quote-formats.md
- [X] T021 [US3] Implement format detection chain in src/parsers/parser.zig (JSON→CSV→TOML→YAML→plaintext order) per contracts/quote-formats.md
- [X] T022 [US3] Add unit tests for each parser in their respective files (malformed input, empty files, UTF-8 edge cases)
- [X] T023 [US3] Integrate parsers with QuoteStore.build() method in src/quote_store.zig (directory walking, file parsing, deduplication)
- [X] T024 [US3] Add QuoteStore.build() integration tests in src/quote_store.zig verifying multi-format loading and deduplication
- [X] T025 [US3] Implement UTF-8 normalization and whitespace trimming in quote loading per contracts/quote-formats.md universal rules

**Checkpoint**: At this point, User Story 3 should be fully functional - quotes load from all 5 formats with deduplication

---

## Phase 4: User Story 6 - Configuration via TOML File (Priority: P1) 🎯 MVP

**Goal**: Enable service configuration via quotez.toml with validation and defaults

**Why Now**: Configuration is required before network servers can bind to ports and operate

**Independent Test**: Create various config files, start service, verify correct behavior (ports, directories, modes)

### Implementation for User Story 6

- [X] T026 [US6] Extend Configuration validation in src/config.zig to check port ranges, positive intervals, valid mode enums per contracts/config-schema.md
- [X] T027 [US6] Implement fatal error handling for missing required fields (directories) with clear exit messages in src/config.zig
- [X] T028 [US6] Implement default application for optional fields (ports, interval, mode) with WARNING logs in src/config.zig
- [X] T029 [US6] Add comprehensive Configuration validation tests in src/config.zig covering all edge cases from contracts/config-schema.md
- [X] T030 [US6] Create main.zig to load Configuration from quotez.toml on startup and handle config errors

**Checkpoint**: At this point, User Story 6 should be fully functional - service reads and validates configuration correctly

---

## Phase 5: User Story 1 - Serve Quotes Over TCP (Priority: P1) 🎯 MVP

**Goal**: Implement RFC 865 TCP QOTD server that sends one quote per connection and closes

**Why Now**: TCP is the primary QOTD protocol and core value proposition

**Independent Test**: Start service, connect via `nc localhost 17`, receive quote, verify connection closes

### Implementation for User Story 1

- [X] T031 [P] [US1] Implement NetworkServer struct in src/servers/tcp.zig with tcp_socket, tcp_addr, and quote_store pointer per data-model.md NetworkServer entity
- [X] T032 [US1] Implement TCP socket binding and listen in src/servers/tcp.zig per contracts/qotd-protocol.md TCP implementation
- [X] T033 [US1] Implement TCP accept-send-close loop in src/servers/tcp.zig (accept connection, get quote from store, send with newline, close)
- [X] T034 [US1] Handle empty quote store case in src/servers/tcp.zig (close immediately without sending) per contracts/qotd-protocol.md
- [X] T035 [US1] Add TCP error handling (ECONNRESET, EPIPE, EAGAIN) per contracts/qotd-protocol.md network errors
- [X] T036 [US1] Integrate TCP server with main event loop in src/main.zig
- [X] T037 [US1] Create integration test in tests/integration/protocol_test.zig for TCP RFC 865 compliance (spawn subprocess, connect, verify quote, verify close)

**Checkpoint**: At this point, User Story 1 should be fully functional - TCP QOTD server works independently

---

## Phase 6: User Story 2 - Serve Quotes Over UDP (Priority: P2)

**Goal**: Implement RFC 865 UDP QOTD server that responds to datagrams with quotes

**Independent Test**: Send UDP datagram via `echo "" | nc -u localhost 17`, receive quote response

### Implementation for User Story 2

- [X] T038 [P] [US2] Extend NetworkServer struct in src/servers/udp.zig with udp_socket and udp_addr per data-model.md
- [X] T039 [US2] Implement UDP socket binding in src/servers/udp.zig per contracts/qotd-protocol.md UDP implementation
- [X] T040 [US2] Implement UDP recvfrom-sendto handler in src/servers/udp.zig (receive datagram, ignore content, get quote, sendto response)
- [X] T041 [US2] Handle empty quote store case in src/servers/udp.zig (silent drop, no response) per contracts/qotd-protocol.md
- [X] T042 [US2] Add UDP error handling (EMSGSIZE, EAGAIN) per contracts/qotd-protocol.md
- [X] T043 [US2] Integrate UDP server with main event loop using poll() multiplexing in src/main.zig
- [X] T044 [US2] Create integration test in tests/integration/protocol_test.zig for UDP RFC 865 compliance

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - TCP and UDP servers coexist

---

## Phase 7: User Story 5 - Quote Selection Modes (Priority: P2)

**Goal**: Enable configuration of selection modes (random, sequential, random-no-repeat, shuffle-cycle)

**Independent Test**: Configure each mode, request multiple quotes, verify selection behavior

### Implementation for User Story 5

- [X] T045 [US5] Verify Selector random mode implementation in src/selector.zig (already in Phase 2, add edge case tests)
- [X] T046 [US5] Implement Selector sequential wraparound logic in src/selector.zig per data-model.md sequential state machine
- [X] T047 [US5] Implement Selector random-no-repeat exhausted set management in src/selector.zig per data-model.md
- [X] T048 [US5] Implement Selector shuffle-cycle Fisher-Yates shuffle and reshuffle triggers in src/selector.zig
- [X] T049 [US5] Implement Selector reset logic for all modes on QuoteStore rebuild per spec.md clarifications
- [X] T050 [US5] Add integration tests in tests/integration/selector_test.zig for each mode's behavior over multiple requests
- [X] T051 [US5] Verify Configuration.selection_mode integration with Selector initialization in src/main.zig

**Checkpoint**: All selection modes should work independently and switch correctly based on config

---

## Phase 8: User Story 4 - Reload Quotes on File Changes (Priority: P3)

**Goal**: Implement file system polling and atomic quote store reload without service interruption

**Independent Test**: Start service, add/modify quote files, wait polling interval, verify new quotes served

### Implementation for User Story 4

- [ ] T052 [P] [US4] Implement FileWatcher entity in src/watcher.zig with directories, snapshots HashMap, and interval per data-model.md FileWatcher
- [ ] T053 [US4] Implement directory walking and stat() collection in src/watcher.zig per research.md file system watching
- [ ] T054 [US4] Implement mtime comparison logic in src/watcher.zig (detect new, modified, deleted files)
- [ ] T055 [US4] Implement FileWatcher.poll() method returning bool for change detection per data-model.md
- [ ] T056 [US4] Add FileWatcher unit tests in src/watcher.zig for change detection scenarios
- [ ] T057 [US4] Implement atomic pointer swap for QuoteStore rebuild in src/main.zig per data-model.md rebuild flow
- [ ] T058 [US4] Integrate FileWatcher.poll() into main event loop timeout in src/main.zig
- [ ] T059 [US4] Trigger QuoteStore.build() on detected changes and swap pointer in src/main.zig
- [ ] T060 [US4] Ensure Selector reset on rebuild per spec.md clarifications (sequential→0, shuffle→reshuffle, etc.)
- [ ] T061 [US4] Create integration test in tests/integration/reload_test.zig verifying non-disruptive reload

**Checkpoint**: At this point, User Story 4 should be fully functional - hot reloading works without service restart

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, deployment artifacts, and validation

- [X] T062 [P] Implement main entry point in src/main.zig with initialization sequence (config→logger→quote store→servers→event loop)
- [X] T063 [P] Add graceful shutdown handling (SIGTERM/SIGINT) in src/main.zig
- [X] T064 [P] Implement poll() multiplexing for TCP and UDP sockets in src/main.zig per research.md networking architecture
- [X] T065 [P] Add startup/shutdown logging per contracts/config-schema.md observability requirements
- [X] T066 [P] Add quote store build logging (files, quotes, duplicates) per data-model.md StoreMetadata
- [X] T067 [P] Create end-to-end integration test in tests/integration/end_to_end_test.zig (full service lifecycle)
- [ ] T068 Verify static binary compilation with `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl`
- [ ] T069 Verify binary size < 5MB per spec.md success criteria SC-009
- [ ] T070 Build Docker scratch image per quickstart.md and verify size < 10MB per spec.md SC-010
- [X] T071 [P] Create sample quotez.toml in repository root matching quickstart.md examples
- [ ] T072 [P] Verify all quickstart.md deployment scenarios (Docker, local, Kubernetes examples)
- [ ] T073 Run full test suite: `zig build test` (all unit and integration tests)
- [ ] T074 Verify performance criteria: TCP/UDP response < 10ms, 100 concurrent connections, 10k quotes < 5s startup per spec.md SC-001 through SC-004

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001-T005) completion - BLOCKS all user stories
- **User Story 3 (Phase 3)**: Depends on Foundational (T006-T014) - BLOCKS US1 and US2
- **User Story 6 (Phase 4)**: Depends on Foundational (T006-T014) - needed before servers start
- **User Story 1 (Phase 5)**: Depends on Foundational + US3 + US6 (T015-T030)
- **User Story 2 (Phase 6)**: Depends on Foundational + US3 + US6 (T015-T030) - Can run parallel to US1
- **User Story 5 (Phase 7)**: Depends on Foundational (T006-T014) - Selection modes already implemented, this phase adds edge cases
- **User Story 4 (Phase 8)**: Depends on all core functionality (US1, US2, US3, US5, US6)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 3 (P1)**: FOUNDATIONAL - Must complete first (quote loading prerequisite)
- **User Story 6 (P1)**: FOUNDATIONAL - Must complete before servers (config prerequisite)
- **User Story 1 (P1)**: Depends on US3 + US6 - Can start after foundational quotes + config
- **User Story 2 (P2)**: Depends on US3 + US6 - Can run parallel to US1 (independent protocol)
- **User Story 5 (P2)**: Depends on US3 - Enhances quote serving, can run parallel to US1/US2
- **User Story 4 (P3)**: Depends on all core stories - Adds operational convenience

### Suggested MVP Scope

**Minimal MVP (Immediate Value)**:
- Phase 1: Setup (T001-T005)
- Phase 2: Foundational (T006-T014)
- Phase 3: US3 - Load Quotes (T015-T025)
- Phase 4: US6 - Configuration (T026-T030)
- Phase 5: US1 - TCP Server (T031-T037)
- Selected Polish: T062-T069 (main entry point, shutdown, binary build)

**Result**: Functional TCP QOTD server loading quotes from multiple formats - deployable single binary

**Full MVP (Complete P1 Stories)**:
- Add Phase 6: US2 - UDP Server (T038-T044)
- Add remaining Phase 9 tasks (T070-T074)

**Result**: Full RFC 865 compliance with TCP + UDP, ready for production

### Within Each User Story

- Tests (unit tests embedded in modules via Zig test blocks)
- Parsers before quote store integration (US3)
- Configuration before server binding (US6)
- Core server logic before integration (US1, US2)
- Selector modes before advanced features (US5)
- File watching before reload integration (US4)

### Parallel Opportunities

**Phase 1 (Setup)**: T003, T004, T005 can run in parallel with T001-T002

**Phase 2 (Foundational)**:
- T008 (Logger) parallel to T006-T007 (Config)
- T009, T012, T013, T014 can run in parallel after T010-T011 complete

**Phase 3 (US3)**:
- T016-T020 (all parsers) can run fully in parallel
- T022 (parser tests) can run in parallel

**Phase 5 (US1)**: T031 can start parallel to T032 (struct definition vs socket setup)

**Phase 6 (US2)**: T038-T042 (entire UDP implementation) can run fully in parallel to Phase 5 if team capacity allows

**Phase 9 (Polish)**: T062-T067, T071-T072 can run in parallel

---

## Parallel Example: User Story 3 (Quote Loading)

```bash
# Terminal 1: Implement plaintext parser
nvim src/parsers/txt.zig  # T016

# Terminal 2: Implement JSON parser
nvim src/parsers/json.zig  # T017

# Terminal 3: Implement CSV parser
nvim src/parsers/csv.zig   # T018

# Terminal 4: Implement TOML parser
nvim src/parsers/toml.zig  # T019

# Terminal 5: Implement YAML parser
nvim src/parsers/yaml.zig  # T020
```

All five parsers (T016-T020) implement the same interface independently and can be developed simultaneously.

---

## Parallel Example: User Stories 1 and 2 (TCP and UDP Servers)

```bash
# Team Member A: TCP server
nvim src/servers/tcp.zig   # T031-T037 (Phase 5)

# Team Member B: UDP server (parallel)
nvim src/servers/udp.zig   # T038-T044 (Phase 6)
```

TCP (US1) and UDP (US2) implementations are independent and can proceed in parallel after foundational work completes.

---

## Implementation Strategy

### MVP-First Approach (Recommended)

1. **Week 1**: Phase 1-2 (Setup + Foundational) - T001 through T014
2. **Week 2**: Phase 3-4 (Quote Loading + Config) - T015 through T030
3. **Week 3**: Phase 5 (TCP Server) - T031 through T037
4. **Week 4**: Phase 6-9 (UDP + Polish) - T038 through T074

**Deliverable**: Fully functional RFC 865 QOTD service with TCP/UDP support, multi-format quote loading, and Docker deployment.

### Incremental Delivery Milestones

**Milestone 1 (MVP)**: Phase 1-2-3-4-5 + selected polish (T001-T037, T062-T069)
- **Deliverable**: TCP QOTD server with quote loading
- **Value**: Basic QOTD service deployable to production

**Milestone 2**: Add Phase 6 (T038-T044)
- **Deliverable**: Full RFC 865 compliance (TCP + UDP)
- **Value**: Complete protocol support

**Milestone 3**: Add Phase 7 (T045-T051)
- **Deliverable**: All selection modes operational
- **Value**: Enhanced user configurability

**Milestone 4**: Add Phase 8 (T052-T061)
- **Deliverable**: Hot reloading without restart
- **Value**: Improved operational convenience

**Milestone 5**: Complete Phase 9 (T070-T074)
- **Deliverable**: Production-ready deployment artifacts
- **Value**: Container images, full test coverage, performance validation

---

## Testing Strategy

### Unit Tests (Embedded in Source Files)

Zig convention: Co-locate tests with implementation using `test "name" { ... }` blocks

**Coverage**:
- src/config.zig: Configuration parsing, validation, defaults (T007, T029)
- src/quote_store.zig: Deduplication, metadata tracking (T011, T024)
- src/selector.zig: All four selection modes (T014, T045-T048)
- src/parsers/*.zig: Each format's parsing edge cases (T022)
- src/watcher.zig: Change detection logic (T056)

**Run**: `zig test src/[file].zig` or `zig build test` for all

### Integration Tests (Separate Directory)

**tests/integration/protocol_test.zig** (T037, T044):
- Spawn quotez subprocess
- Test TCP: connect, receive quote, verify close
- Test UDP: send datagram, receive response

**tests/integration/reload_test.zig** (T061):
- Start service with initial quotes
- Modify quote files
- Wait for polling interval
- Verify new quotes appear in responses

**tests/integration/end_to_end_test.zig** (T067):
- Full lifecycle: startup → serve → reload → shutdown
- Verify all components work together

**tests/integration/selector_test.zig** (T050):
- Test each selection mode over multiple requests
- Verify behavioral contracts (wraparound, no-repeat, shuffle)

**Run**: `zig build test` (build system includes integration tests)

### Manual Testing (Quickstart Validation)

**T072**: Follow all quickstart.md scenarios:
- Docker deployment
- Local binary execution
- Kubernetes manifests
- Various configuration examples

---

## Task Count Summary

**Total Tasks**: 74

**Breakdown by Phase**:
- Phase 1 (Setup): 5 tasks
- Phase 2 (Foundational): 9 tasks (BLOCKING)
- Phase 3 (US3 - Quote Loading): 11 tasks
- Phase 4 (US6 - Configuration): 5 tasks
- Phase 5 (US1 - TCP Server): 7 tasks
- Phase 6 (US2 - UDP Server): 7 tasks
- Phase 7 (US5 - Selection Modes): 7 tasks
- Phase 8 (US4 - Hot Reload): 10 tasks
- Phase 9 (Polish): 13 tasks

**Breakdown by User Story**:
- US1 (TCP Server): 7 tasks
- US2 (UDP Server): 7 tasks
- US3 (Quote Loading): 11 tasks
- US4 (Hot Reload): 10 tasks
- US5 (Selection Modes): 7 tasks
- US6 (Configuration): 5 tasks
- Setup/Foundational/Polish: 27 tasks

**Parallel Opportunities**: 23 tasks marked [P] can run in parallel when phase dependencies allow

**Independent Test Criteria**:
- US3: Place files → verify parsing → check logs
- US6: Create configs → start service → verify behavior
- US1: Connect TCP → receive quote → verify close
- US2: Send UDP → receive quote
- US5: Configure mode → request quotes → verify pattern
- US4: Modify files → wait interval → verify reload

---

## Format Validation

✅ **All tasks follow checklist format**: `- [ ] [ID] [P?] [Story] Description with file path`

✅ **All user story tasks have [Story] labels**: US1, US2, US3, US4, US5, US6

✅ **Setup/Foundational/Polish tasks have NO story labels** (correct per format rules)

✅ **Parallel tasks marked with [P]** where applicable (23 tasks)

✅ **File paths included** in all task descriptions

✅ **Sequential task IDs**: T001 through T074

---

## Ready for Implementation

This task breakdown is immediately executable by an LLM or development team. Each task:
- Has clear acceptance criteria
- Specifies exact file paths
- Follows Zig and quotez architectural patterns
- Maps directly to requirements from spec.md
- Enables incremental delivery
- Supports parallel execution where possible

**Recommended Starting Point**: T001 (Create project structure)

**Recommended MVP Target**: T001-T037 + T062-T069 (Complete TCP QOTD server)
