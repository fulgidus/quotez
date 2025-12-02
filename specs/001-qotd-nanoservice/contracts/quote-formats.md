# Quote File Formats Contract

**Feature**: 001-qotd-nanoservice  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This document defines the supported quote file formats, detection order, parsing rules, and error handling for quotez. The service supports five file formats with automatic format detection and error-tolerant parsing.

---

## Format Detection Order

When encountering a file, quotez attempts format detection in this strict order:

1. **JSON** → Check extension `.json`, validate first non-whitespace char is `{` or `[`
2. **CSV** → Check extension `.csv`, look for comma/tab delimiters in first line
3. **TOML** → Check extension `.toml`, look for `[section]` or `key = value` patterns
4. **YAML** → Check extension `.yaml` or `.yml`, look for `---` or key-colon patterns
5. **Plaintext** → Fallback for any other extension (`.txt`, no extension, or detection failure)

**Rationale**: Structured formats (JSON, CSV, TOML, YAML) are attempted first for explicit quote extraction. Plaintext is the fallback for simple line-delimited quotes.

---

## Format Specifications

### 1. JSON Format

**File Extensions**: `.json`

**Supported Structures**:

**Array of Strings** (Preferred):
```json
[
  "The only way to do great work is to love what you do.",
  "Innovation distinguishes between a leader and a follower.",
  "Stay hungry, stay foolish."
]
```

**Object with Quote Array**:
```json
{
  "quotes": [
    "First quote",
    "Second quote"
  ]
}
```

**Array of Objects** (with `quote` or `text` field):
```json
[
  {
    "quote": "Be yourself; everyone else is already taken.",
    "author": "Oscar Wilde"
  },
  {
    "quote": "To be or not to be, that is the question.",
    "author": "William Shakespeare"
  }
]
```

**Parsing Rules**:
- Use `std.json.parseFromSlice()` from Zig standard library
- Extract strings from:
  1. Root array of strings (direct quotes)
  2. Root object with `"quotes"` key (array of strings)
  3. Array of objects: Extract `"quote"` or `"text"` field from each object
- Ignore non-string values (numbers, booleans, null)
- Ignore objects without `quote`/`text` field
- **Author concatenation**: If object has `"author"` field, concatenate as: `"{{quote}} — {{author}}"`
- Format uses em dash (—) as separator between quote and author

**Error Handling**:
- Malformed JSON (syntax error): Skip file, log ERROR
- Empty array or object: Skip file, log WARNING
- Mixed types in array: Extract strings, ignore others
- Missing `quote`/`text` in object: Skip that object, continue

**Example Valid Files**:

`quotes.json`:
```json
[
  "The best time to plant a tree was 20 years ago. The second best time is now.",
  "It does not matter how slowly you go as long as you do not stop."
]
```

`wisdom.json`:
```json
{
  "quotes": [
    "Do or do not. There is no try.",
    "Fear is the path to the dark side."
  ]
}
```

---

### 2. CSV Format

**File Extensions**: `.csv`

**Supported Delimiters**: Comma (`,`), Tab (`\t`)

**Structure**: Each row contains quote text in the first column. If second column exists, it's treated as author.

**Standard Format** (Quote and author in columns):
```csv
quote,author
"The only impossible journey is the one you never begin.","Tony Robbins"
"Life is what happens when you're busy making other plans.","John Lennon"
```

**Quote-Only Format** (No header):
```csv
The greatest glory in living lies not in never falling, but in rising every time we fall.
The way to get started is to quit talking and begin doing.
```

**Parsing Rules**:
- Detect delimiter: Check first line for `,` or `\t` (prefer comma)
- **First row handling**:
  - If first row contains `"quote"`, `"text"`, or `"content"` header: Skip header row
  - Otherwise: Treat first row as quote
- Extract first column from each row (quote text)
- If second column exists, extract as author
- **Author concatenation**: If author column present, format as: `"{{quote}} — {{author}}"`
- Trim whitespace from extracted text
- Ignore empty rows
- Handle quoted fields: `"Text with, comma"` → `Text with, comma`

**Error Handling**:
- Malformed CSV (unclosed quotes): Best-effort parsing, skip malformed rows
- Empty file: Skip file, log WARNING
- Rows with no columns: Skip row
- Delimiter detection failure: Fall back to plaintext parsing

**Example Valid Files**:

`quotes.csv`:
```csv
quote,author,year
"Be the change you wish to see in the world.","Mahatma Gandhi",1945
"You miss 100% of the shots you don't take.","Wayne Gretzky",1983
```

`simple.csv` (no header):
```csv
Success is not final, failure is not fatal: It is the courage to continue that counts.
It always seems impossible until it's done.
```

---

### 3. TOML Format

**File Extensions**: `.toml`

**Supported Structures**:

**Array of Strings** (Top-level `quotes` key):
```toml
quotes = [
    "The future belongs to those who believe in the beauty of their dreams.",
    "It is during our darkest moments that we must focus to see the light."
]
```

**Array of Tables** (with `text` or `quote` field):
```toml
[[quotes]]
text = "Believe you can and you're halfway there."
author = "Theodore Roosevelt"

[[quotes]]
text = "The only limit to our realization of tomorrow is our doubts of today."
author = "Franklin D. Roosevelt"
```

**Parsing Rules**:
- Use inline TOML parser or `zig-toml` package
- Extract strings from:
  1. Top-level `quotes = [...]` array
  2. `[[quotes]]` array of tables: Extract `text` or `quote` field
- Ignore non-string values
- Ignore tables without `text`/`quote` field
- Author/metadata fields ignored

**Error Handling**:
- Malformed TOML (syntax error): Skip file, log ERROR
- Missing `quotes` key: Skip file, log WARNING
- Empty array: Skip file, log WARNING

**Example Valid File**:

`quotes.toml`:
```toml
# Collection of motivational quotes

quotes = [
    "The purpose of our lives is to be happy.",
    "Life is really simple, but we insist on making it complicated."
]
```

---

### 4. YAML Format

**File Extensions**: `.yaml`, `.yml`

**Supported Structures**:

**List of Strings**:
```yaml
---
- The best revenge is massive success.
- I have not failed. I've just found 10,000 ways that won't work.
- The only way to do great work is to love what you do.
```

**List of Objects** (with `quote` or `text` field):
```yaml
---
- quote: "Life is 10% what happens to us and 90% how we react to it."
  author: "Charles R. Swindoll"
- quote: "Your time is limited, don't waste it living someone else's life."
  author: "Steve Jobs"
```

**Object with Quotes Array**:
```yaml
---
quotes:
  - "The mind is everything. What you think you become."
  - "The best time to plant a tree was 20 years ago. The second best time is now."
```

**Parsing Rules**:
- Use minimal YAML parser (subset support):
  - Recognize `---` document separator
  - Parse lists (`- item`)
  - Parse key-value pairs (`key: value`)
  - Handle quoted strings
- Extract strings from:
  1. Root-level list of strings
  2. Root-level `quotes` key containing list
  3. List of objects: Extract `quote` or `text` field
- Ignore complex YAML features (anchors, aliases, multi-line) in MVP

**Error Handling**:
- Malformed YAML (indentation errors): Skip file, log ERROR
- Complex YAML features: Best-effort parsing, skip unsupported constructs
- Empty document: Skip file, log WARNING

**Example Valid File**:

`quotes.yaml`:
```yaml
---
- "The greatest glory in living lies not in never falling, but in rising every time we fall."
- "The way to get started is to quit talking and begin doing."
- "If life were predictable it would cease to be life, and be without flavor."
```

---

### 5. Plaintext Format

**File Extensions**: `.txt`, or any unrecognized extension (fallback)

**Structure**: One quote per line, empty lines ignored.

**Format**:
```
The only impossible journey is the one you never begin.
Life is what happens when you're busy making other plans.

The greatest glory in living lies not in never falling, but in rising every time we fall.
```

**Parsing Rules**:
- Split file content by newlines (`\n`)
- Trim leading/trailing whitespace from each line
- Skip empty lines (after trimming)
- Each non-empty line is one quote

**Error Handling**:
- Empty file: Skip file, log WARNING
- File with only whitespace/empty lines: Skip file, log WARNING
- Encoding issues: Replace invalid UTF-8 with replacement character (U+FFFD)

**Example Valid File**:

`quotes.txt`:
```
The purpose of our lives is to be happy.
Life is really simple, but we insist on making it complicated.
Get busy living or get busy dying.
```

---

## Universal Parsing Rules

### Whitespace Normalization

Applied to **all formats** after extraction:

1. **Trim leading/trailing whitespace**: `"  Quote  "` → `"Quote"`
2. **Collapse internal whitespace**: `"Quote  with   spaces"` → `"Quote with spaces"`
3. **Replace newlines with spaces**: Multi-line quotes become single-line
4. **Remove empty results**: Quotes that become empty after trimming are discarded

### UTF-8 Encoding

- All quote files MUST be UTF-8 or ASCII-compatible
- Invalid UTF-8 sequences replaced with Unicode replacement character (U+FFFD: �)
- BOM (Byte Order Mark) at file start is stripped if present

### Empty Line Handling

- Empty lines (or lines with only whitespace) are **always skipped**
- Applies to all formats, including plaintext

### Quote Length

- **No hard length limit** in MVP
- **Practical limit**: 512 bytes typical for QOTD protocol (see qotd-protocol.md)
- Quotes exceeding 512 bytes are allowed but may cause issues with UDP fragmentation

---

## File Discovery

### Directory Scanning

- **Recursive scanning**: All subdirectories under configured `directories` are scanned
- **Symlinks**: Follow symlinks to files and directories (detect cycles to prevent infinite loops)
- **Hidden files**: Files starting with `.` are **included** (e.g., `.quotes.json`)
- **File permissions**: Unreadable files are skipped with WARNING log

### Example Directory Structure

```
/data/quotes/
├── general.txt              ← Parsed as plaintext
├── wisdom.json              ← Parsed as JSON
├── tech/
│   ├── programming.csv      ← Parsed as CSV
│   └── devops.yaml          ← Parsed as YAML
├── custom/
│   └── quotes.toml          ← Parsed as TOML
└── .hidden-quotes.txt       ← Parsed (hidden file included)
```

**Result**: All 6 files are parsed, quotes extracted, merged, and deduplicated.

---

## Error Handling Summary

### Fatal Errors (Service Exit)

**None** for file parsing. Malformed quote files are non-fatal.

### Non-Fatal Errors (Log and Continue)

| Error | Behavior | Log Level |
|-------|----------|-----------|
| Malformed JSON/TOML/YAML | Skip file, continue with others | ERROR |
| CSV with unclosed quotes | Best-effort parse, skip bad rows | WARNING |
| Empty file (0 bytes) | Skip file | WARNING |
| File only whitespace/empty lines | Skip file | WARNING |
| Unreadable file (permissions) | Skip file | WARNING |
| Invalid UTF-8 encoding | Replace with U+FFFD, continue | WARNING |
| Directory doesn't exist | Skip directory | WARNING |

**Principle**: Service is **error-tolerant** and continues operation with whatever valid quotes it can extract.

---

## Performance Considerations

### File Size Limits

- **MVP**: No artificial file size limit
- **Memory**: File content loaded entirely into memory during parsing
- **Practical Limit**: Assume files fit in available RAM (typical: < 100MB per file)

### Parsing Performance

| Format | Complexity | Notes |
|--------|------------|-------|
| JSON | O(n) | Fast with std.json |
| CSV | O(n) | Simple split + trim |
| TOML | O(n) | Inline parser adequate |
| YAML | O(n) | Minimal subset parser |
| TXT | O(n) | Split by newlines |

**Expected Performance**: 10,000 quotes from 20 mixed-format files parsed in < 5 seconds.

---

## Testing & Validation

### Format Detection Tests

| File Name | Content Start | Detected Format |
|-----------|---------------|-----------------|
| `quotes.json` | `[` | JSON |
| `quotes.csv` | `quote,author` | CSV |
| `quotes.toml` | `quotes = [` | TOML |
| `quotes.yaml` | `---\n- ` | YAML |
| `quotes.txt` | `Some quote` | Plaintext |
| `quotes.unknown` | `Random text` | Plaintext (fallback) |

### Parsing Tests

**Test Case: Mixed Formats**
```
/data/quotes/
├── a.json  → ["Quote 1", "Quote 2"]
├── b.csv   → Quote 2\nQuote 3
└── c.txt   → Quote 3\nQuote 4
```

**Expected Result**:
- Total parsed: 6 quotes
- After deduplication: 4 unique quotes ("Quote 1", "Quote 2", "Quote 3", "Quote 4")
- Duplicates removed: 2

**Test Case: Malformed File**
```
malformed.json:
{ "quotes": [ "Valid quote", syntax error here }
```

**Expected Behavior**:
- Log: `ERROR file_parse_error path=malformed.json format=json reason="unexpected token"`
- File skipped, other files parsed successfully

---

## Example Parsing Workflow

### Input Files

**quotes.json**:
```json
["First quote", "Second quote"]
```

**quotes.csv**:
```csv
quote
Second quote
Third quote
```

**quotes.txt**:
```
Third quote
Fourth quote
```

### Parsing Steps

1. **File Discovery**: Find 3 files
2. **Format Detection**:
   - `quotes.json` → JSON (extension + content check)
   - `quotes.csv` → CSV (extension + delimiter check)
   - `quotes.txt` → Plaintext (fallback)
3. **Extraction**:
   - JSON: Extract `["First quote", "Second quote"]`
   - CSV: Extract `["Second quote", "Third quote"]` (header skipped)
   - TXT: Extract `["Third quote", "Fourth quote"]`
4. **Normalization**: Trim whitespace, validate UTF-8
5. **Deduplication**:
   - "First quote" → hash_1
   - "Second quote" → hash_2 (appears 2x, keep 1)
   - "Third quote" → hash_3 (appears 2x, keep 1)
   - "Fourth quote" → hash_4
6. **Final Store**: `["First quote", "Second quote", "Third quote", "Fourth quote"]` (4 unique)

---

## References

- [JSON Specification](https://www.json.org/json-en.html)
- [CSV RFC 4180](https://www.rfc-editor.org/rfc/rfc4180.html)
- [TOML v1.0.0](https://toml.io/en/v1.0.0)
- [YAML 1.2](https://yaml.org/spec/1.2/spec.html)
- quotez Constitution v1.0.0 (Principle II: Local Quote Loading)

---

## Changelog

**2025-12-01**: Initial quote file formats specification for MVP
