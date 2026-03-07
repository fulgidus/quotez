# quotez Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-12-01

## Active Technologies

- Zig 0.15.2 (MANDATORY) (001-qotd-nanoservice)

## Project Structure

```text
src/
tests/
```

## Commands

# Build and test commands for Zig 0.15.2
zig build            # Build the project
zig build run        # Build and run
zig build test       # Run all tests

## Code Style

Zig 0.15.2: Follow standard conventions

## Recent Changes

- 001-qotd-nanoservice: Updated to Zig 0.15.2 (MANDATORY)

<!-- MANUAL ADDITIONS START -->
## Git Commit Constraints (HARD RULES)

- **Preserve user identity**: NEVER change git config (user.name, user.email). NEVER use --author overrides.
- **No AI attribution**: NEVER add Co-authored-by trailers, "Ultraworked" footers, or any third-party contributor references to commits.
- **No agent branding in commits**: NEVER use agent names (Sisyphus, Atlas, etc.) in commit scopes, subjects, or bodies.
- **Commit messages must be clean**: No references to `.sisyphus/`, evidence files, plan files, or orchestration artifacts in commit messages.
- **No root directory pollution**: NEVER create scratch files, test binaries, or temporary files in the project root directory.
<!-- MANUAL ADDITIONS END -->
