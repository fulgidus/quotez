# REST API Contract

**Feature**: 001-qotd-nanoservice  
**Format**: JSON  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This document defines the complete HTTP REST API for quotez quote management and operational control. The API provides endpoints for CRUD operations on quotes, configuration management, status monitoring, and maintenance operations. All endpoints use JSON for request and response bodies.

The API is designed to support:
- **Quote Management**: Create, read, update, delete quotes via HTTP
- **Configuration Control**: Runtime configuration adjustments (non-persistent)
- **Status Monitoring**: Health checks and operational metrics
- **Maintenance**: Reload operations and maintenance mode control

---

## Authentication

All `/api/*` endpoints require **HTTP Basic Authentication** (RFC 7617).

### Authentication Scheme

- **Type**: HTTP Basic Auth
- **Header**: `Authorization: Basic <base64(username:password)>`
- **Scope**: All endpoints under `/api/*` prefix
- **Unprotected Endpoints**: `/health`, `/ready` (no authentication required)

### Authentication Failure Response

**Status Code**: `401 Unauthorized`

**Response Header**:
```
WWW-Authenticate: Basic realm="quotez API"
```

**Response Body**:
```json
{
  "error": "Unauthorized",
  "code": 401
}
```

### Implementation Notes

- Credentials are validated against a simple in-memory store (MVP: hardcoded or environment-based)
- No session management; each request must include credentials
- Credentials are case-sensitive
- Empty username or password is invalid

---

## Error Response Format

All error responses follow a consistent format:

```json
{
  "error": "Human-readable error message",
  "code": <HTTP_STATUS_CODE>
}
```

### Common Error Codes

| Code | Meaning | Typical Cause |
|------|---------|---------------|
| 400 | Bad Request | Invalid JSON, missing required fields, validation failure |
| 401 | Unauthorized | Missing or invalid credentials |
| 404 | Not Found | Quote ID does not exist |
| 409 | Conflict | Duplicate quote text |
| 500 | Internal Server Error | Unexpected server error |
| 503 | Service Unavailable | Maintenance mode enabled |

---

## Constraints

- **Request Body Size**: Maximum 64 KB per request
- **Content-Type**: All requests and responses use `application/json`
- **Quote IDs**: Integer indices (0-based), assigned sequentially, may change across reloads
- **Quote Text**: Non-empty string, max 4096 characters
- **Source Field**: Read-only, indicates which file the quote came from
- **Timeout**: 30 seconds per request

---

## Endpoints

### Health Check (Unprotected)

#### `GET /health`

Health check endpoint for load balancers and monitoring systems.

**Authentication**: Not required

**Request**:
```
GET /health HTTP/1.1
Host: localhost:8080
```

**Response** (200 OK):
```json
{
  "status": "ok"
}
```

**Status Codes**:
- `200 OK`: Service is running

---

### Readiness Check (Unprotected)

#### `GET /ready`

Readiness check endpoint. Returns 503 if no quotes are loaded or maintenance mode is enabled.

**Authentication**: Not required

**Request**:
```
GET /ready HTTP/1.1
Host: localhost:8080
```

**Response** (200 OK):
```json
{
  "status": "ready",
  "quotes": 42
}
```

**Response** (503 Service Unavailable):
```json
{
  "status": "unavailable",
  "reason": "maintenance mode enabled"
}
```

**Status Codes**:
- `200 OK`: Service is ready to serve quotes
- `503 Service Unavailable`: No quotes loaded or maintenance mode enabled

---

### Quote Management Endpoints

#### `GET /api/quotes`

Retrieve all quotes in the store.

**Authentication**: Required (Basic Auth)

**Request**:
```
GET /api/quotes HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
```

**Response** (200 OK):
```json
{
  "quotes": [
    {
      "id": 0,
      "text": "The only way to do great work is to love what you do.",
      "source": "/data/quotes/famous.json"
    },
    {
      "id": 1,
      "text": "Innovation distinguishes between a leader and a follower.",
      "source": "/data/quotes/famous.json"
    },
    {
      "id": 2,
      "text": "Life is what happens when you're busy making other plans.",
      "source": "/data/quotes/api-managed.json"
    }
  ],
  "count": 3
}
```

**Status Codes**:
- `200 OK`: Quotes retrieved successfully
- `401 Unauthorized`: Missing or invalid credentials
- `503 Service Unavailable`: Maintenance mode enabled

**Notes**:
- Returns empty array if no quotes are loaded
- IDs are 0-based indices
- Source field indicates which file the quote came from
- Quotes are returned in store order (not sorted)

---

#### `GET /api/quotes/:id`

Retrieve a single quote by ID.

**Authentication**: Required (Basic Auth)

**Request**:
```
GET /api/quotes/0 HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
```

**Response** (200 OK):
```json
{
  "id": 0,
  "text": "The only way to do great work is to love what you do.",
  "source": "/data/quotes/famous.json"
}
```

**Response** (404 Not Found):
```json
{
  "error": "Quote not found",
  "code": 404
}
```

**Status Codes**:
- `200 OK`: Quote retrieved successfully
- `401 Unauthorized`: Missing or invalid credentials
- `404 Not Found`: Quote ID does not exist
- `503 Service Unavailable`: Maintenance mode enabled

**Notes**:
- ID must be a valid integer
- ID must be in range [0, quote_count - 1]

---

#### `POST /api/quotes`

Create a new quote.

**Authentication**: Required (Basic Auth)

**Request**:
```
POST /api/quotes HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "text": "The future belongs to those who believe in the beauty of their dreams."
}
```

**Response** (201 Created):
```json
{
  "id": 42,
  "text": "The future belongs to those who believe in the beauty of their dreams."
}
```

**Response** (400 Bad Request - Empty Text):
```json
{
  "error": "Quote text cannot be empty",
  "code": 400
}
```

**Response** (409 Conflict - Duplicate):
```json
{
  "error": "Quote already exists",
  "code": 409
}
```

**Status Codes**:
- `201 Created`: Quote created successfully
- `400 Bad Request`: Missing or empty text field
- `401 Unauthorized`: Missing or invalid credentials
- `409 Conflict`: Quote text already exists in store
- `503 Service Unavailable`: Maintenance mode enabled

**Notes**:
- Request body must contain `text` field (required)
- Text must be non-empty string
- Text must be <= 4096 characters
- Duplicate detection is case-sensitive, exact match
- New quotes are stored in `/data/quotes/api-managed.json`
- Assigned ID is the next available index
- Source field is automatically set to `/data/quotes/api-managed.json`

---

#### `PUT /api/quotes/:id`

Update an existing quote.

**Authentication**: Required (Basic Auth)

**Request**:
```
PUT /api/quotes/0 HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "text": "Updated quote text"
}
```

**Response** (200 OK):
```json
{
  "id": 0,
  "text": "Updated quote text"
}
```

**Response** (404 Not Found):
```json
{
  "error": "Quote not found",
  "code": 404
}
```

**Status Codes**:
- `200 OK`: Quote updated successfully
- `400 Bad Request`: Missing or empty text field
- `401 Unauthorized`: Missing or invalid credentials
- `404 Not Found`: Quote ID does not exist
- `503 Service Unavailable`: Maintenance mode enabled

**Notes**:
- Request body must contain `text` field (required)
- Text must be non-empty string
- Text must be <= 4096 characters
- Only quotes created via API can be updated (source must be `/data/quotes/api-managed.json`)
- Attempting to update quotes from other sources returns 404

---

#### `DELETE /api/quotes/:id`

Delete a quote.

**Authentication**: Required (Basic Auth)

**Request**:
```
DELETE /api/quotes/0 HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
```

**Response** (200 OK):
```json
{
  "status": "deleted"
}
```

**Response** (404 Not Found):
```json
{
  "error": "Quote not found",
  "code": 404
}
```

**Status Codes**:
- `200 OK`: Quote deleted successfully
- `401 Unauthorized`: Missing or invalid credentials
- `404 Not Found`: Quote ID does not exist
- `503 Service Unavailable`: Maintenance mode enabled

**Notes**:
- Only quotes created via API can be deleted (source must be `/data/quotes/api-managed.json`)
- Attempting to delete quotes from other sources returns 404
- After deletion, remaining quotes keep their IDs (no reindexing)

---

### Operational Endpoints

#### `GET /api/status`

Retrieve current operational status and metrics.

**Authentication**: Required (Basic Auth)

**Request**:
```
GET /api/status HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
```

**Response** (200 OK):
```json
{
  "status": "ok",
  "quotes": 42,
  "mode": "random",
  "uptime_seconds": 3600,
  "polling_interval": 60
}
```

**Response** (200 OK - Maintenance Mode):
```json
{
  "status": "maintenance",
  "quotes": 42,
  "mode": "random",
  "uptime_seconds": 3600,
  "polling_interval": 60
}
```

**Status Codes**:
- `200 OK`: Status retrieved successfully
- `401 Unauthorized`: Missing or invalid credentials

**Response Fields**:
- `status`: `"ok"` or `"maintenance"`
- `quotes`: Total number of quotes in store
- `mode`: Current selection mode (`"random"`, `"sequential"`, `"random-no-repeat"`, `"shuffle-cycle"`)
- `uptime_seconds`: Seconds since service started
- `polling_interval`: File polling interval in seconds

---

#### `GET /api/config`

Retrieve current runtime configuration.

**Authentication**: Required (Basic Auth)

**Request**:
```
GET /api/config HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
```

**Response** (200 OK):
```json
{
  "selection_mode": "random",
  "polling_interval": 60,
  "directories": [
    "/data/quotes",
    "/etc/quotez/custom"
  ]
}
```

**Status Codes**:
- `200 OK`: Configuration retrieved successfully
- `401 Unauthorized`: Missing or invalid credentials

**Response Fields**:
- `selection_mode`: Current quote selection mode
- `polling_interval`: File polling interval in seconds
- `directories`: List of directories being scanned for quotes

**Notes**:
- This reflects the current runtime configuration
- Changes made via PATCH are reflected here
- Configuration is NOT persisted to `quotez.toml`

---

#### `PATCH /api/config`

Update runtime configuration (non-persistent).

**Authentication**: Required (Basic Auth)

**Request** (Update Selection Mode):
```
PATCH /api/config HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "selection_mode": "shuffle-cycle"
}
```

**Request** (Update Polling Interval):
```
PATCH /api/config HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "polling_interval": 120
}
```

**Request** (Update Both):
```
PATCH /api/config HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "selection_mode": "sequential",
  "polling_interval": 30
}
```

**Response** (200 OK):
```json
{
  "status": "ok"
}
```

**Response** (400 Bad Request - Invalid Mode):
```json
{
  "error": "Invalid selection mode: 'invalid'. Must be one of: random, sequential, random-no-repeat, shuffle-cycle",
  "code": 400
}
```

**Response** (400 Bad Request - Invalid Interval):
```json
{
  "error": "Polling interval must be positive",
  "code": 400
}
```

**Status Codes**:
- `200 OK`: Configuration updated successfully
- `400 Bad Request`: Invalid field value
- `401 Unauthorized`: Missing or invalid credentials
- `503 Service Unavailable`: Maintenance mode enabled

**Allowed Fields**:
- `selection_mode`: One of `"random"`, `"sequential"`, `"random-no-repeat"`, `"shuffle-cycle"`
- `polling_interval`: Positive integer (seconds)

**Notes**:
- At least one field must be provided
- Changes are applied immediately
- Changes are NOT persisted to `quotez.toml`
- Changes are lost on service restart
- Unknown fields are ignored

---

#### `POST /api/reload`

Trigger an immediate reload of quotes from all configured directories.

**Authentication**: Required (Basic Auth)

**Request**:
```
POST /api/reload HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json
```

**Response** (200 OK):
```json
{
  "status": "ok",
  "quotes": 42
}
```

**Status Codes**:
- `200 OK`: Reload completed successfully
- `401 Unauthorized`: Missing or invalid credentials
- `503 Service Unavailable`: Maintenance mode enabled

**Response Fields**:
- `status`: Always `"ok"` on success
- `quotes`: Total number of quotes after reload

**Notes**:
- Blocks until reload completes
- Deduplicates quotes across all files
- Resets selection state (e.g., sequential counter, shuffle seed)
- May take several seconds for large quote collections
- Timeout: 30 seconds

---

#### `POST /api/maintenance`

Enable or disable maintenance mode.

**Authentication**: Required (Basic Auth)

**Request** (Enable Maintenance):
```
POST /api/maintenance HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "enabled": true
}
```

**Request** (Disable Maintenance):
```
POST /api/maintenance HTTP/1.1
Host: localhost:8080
Authorization: Basic dXNlcjpwYXNz
Content-Type: application/json

{
  "enabled": false
}
```

**Response** (200 OK):
```json
{
  "status": "ok",
  "enabled": true
}
```

**Status Codes**:
- `200 OK`: Maintenance mode updated successfully
- `400 Bad Request`: Missing or invalid `enabled` field
- `401 Unauthorized`: Missing or invalid credentials

**Response Fields**:
- `status`: Always `"ok"` on success
- `enabled`: Current maintenance mode state

**Behavior**:
- When enabled: `/ready` returns 503, `/api/quotes` endpoints return 503
- When disabled: Service returns to normal operation
- Does not affect `/health` endpoint
- Does not affect `/ready` if quotes are loaded

**Notes**:
- Useful for graceful shutdown or maintenance windows
- Does not stop the service
- Can be toggled on/off multiple times

---

## Request/Response Examples

### Complete Quote Creation Workflow

**1. Check Status**:
```bash
curl -u user:pass http://localhost:8080/api/status
```

**2. Create Quote**:
```bash
curl -u user:pass -X POST http://localhost:8080/api/quotes \
  -H "Content-Type: application/json" \
  -d '{"text": "New quote"}'
```

**3. Retrieve Quote**:
```bash
curl -u user:pass http://localhost:8080/api/quotes/42
```

**4. Update Quote**:
```bash
curl -u user:pass -X PUT http://localhost:8080/api/quotes/42 \
  -H "Content-Type: application/json" \
  -d '{"text": "Updated quote"}'
```

**5. Delete Quote**:
```bash
curl -u user:pass -X DELETE http://localhost:8080/api/quotes/42
```

---

## API Design Principles

### ID Management

- **Type**: Integer (0-based index)
- **Assignment**: Sequential, assigned at creation time
- **Stability**: IDs may change across reloads (not stable identifiers)
- **Reuse**: Deleted IDs are not reused
- **Scope**: Global across all quotes

### Quote Lifecycle

1. **Creation**: Via `POST /api/quotes` → stored in `/data/quotes/api-managed.json`
2. **Retrieval**: Via `GET /api/quotes` or `GET /api/quotes/:id`
3. **Update**: Via `PUT /api/quotes/:id` (API-managed quotes only)
4. **Deletion**: Via `DELETE /api/quotes/:id` (API-managed quotes only)
5. **Reload**: Via `POST /api/reload` → rebuilds store from all files

### Configuration Behavior

- **Runtime-Only**: Changes via `PATCH /api/config` are not persisted
- **Immediate Effect**: Changes take effect immediately
- **Loss on Restart**: Changes are lost when service restarts
- **Reload Impact**: `POST /api/reload` resets selection state but preserves config

### Maintenance Mode

- **Purpose**: Graceful shutdown, maintenance windows, traffic control
- **Effect**: Returns 503 for `/ready` and `/api/*` endpoints
- **Scope**: Does not affect `/health` endpoint
- **Reversible**: Can be toggled on/off multiple times

---

## HTTP Headers

### Request Headers

| Header | Required | Example |
|--------|----------|---------|
| `Authorization` | Yes (for `/api/*`) | `Basic dXNlcjpwYXNz` |
| `Content-Type` | Yes (for POST/PUT/PATCH) | `application/json` |
| `Content-Length` | No | `256` |

### Response Headers

| Header | Condition | Example |
|--------|-----------|---------|
| `Content-Type` | Always | `application/json; charset=utf-8` |
| `Content-Length` | Always | `256` |
| `WWW-Authenticate` | On 401 | `Basic realm="quotez API"` |

---

## Status Code Summary

| Code | Endpoint | Meaning |
|------|----------|---------|
| 200 | All | Success (GET, PUT, PATCH, DELETE, POST) |
| 201 | POST /api/quotes | Quote created |
| 400 | POST/PUT/PATCH | Invalid request |
| 401 | All `/api/*` | Missing/invalid credentials |
| 404 | GET/PUT/DELETE /api/quotes/:id | Quote not found |
| 409 | POST /api/quotes | Duplicate quote |
| 503 | All `/api/*` | Maintenance mode or no quotes |
| 503 | GET /ready | Maintenance mode or no quotes |

---

## Endpoint Summary Table

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/health` | No | Health check |
| GET | `/ready` | No | Readiness check |
| GET | `/api/quotes` | Yes | List all quotes |
| GET | `/api/quotes/:id` | Yes | Get single quote |
| POST | `/api/quotes` | Yes | Create quote |
| PUT | `/api/quotes/:id` | Yes | Update quote |
| DELETE | `/api/quotes/:id` | Yes | Delete quote |
| GET | `/api/status` | Yes | Get status |
| GET | `/api/config` | Yes | Get config |
| PATCH | `/api/config` | Yes | Update config |
| POST | `/api/reload` | Yes | Reload quotes |
| POST | `/api/maintenance` | Yes | Toggle maintenance |

---

## Testing & Validation

### Test Cases

| Scenario | Method | Path | Expected |
|----------|--------|------|----------|
| Health check | GET | /health | 200 |
| Ready (no quotes) | GET | /ready | 503 |
| Ready (with quotes) | GET | /ready | 200 |
| List quotes | GET | /api/quotes | 200 + array |
| Get quote (exists) | GET | /api/quotes/0 | 200 + quote |
| Get quote (missing) | GET | /api/quotes/999 | 404 |
| Create quote | POST | /api/quotes | 201 + id |
| Create duplicate | POST | /api/quotes | 409 |
| Update quote | PUT | /api/quotes/0 | 200 |
| Update missing | PUT | /api/quotes/999 | 404 |
| Delete quote | DELETE | /api/quotes/0 | 200 |
| Delete missing | DELETE | /api/quotes/999 | 404 |
| Get status | GET | /api/status | 200 + metrics |
| Get config | GET | /api/config | 200 + config |
| Update config | PATCH | /api/config | 200 |
| Reload quotes | POST | /api/reload | 200 + count |
| Enable maintenance | POST | /api/maintenance | 200 |
| Disable maintenance | POST | /api/maintenance | 200 |
| No auth | GET | /api/quotes | 401 |
| Bad auth | GET | /api/quotes | 401 |

---

## References

- [RFC 7231 - HTTP/1.1 Semantics and Content](https://tools.ietf.org/html/rfc7231)
- [RFC 7617 - The 'Basic' HTTP Authentication Scheme](https://tools.ietf.org/html/rfc7617)
- [JSON Specification](https://www.json.org/)
- quotez Constitution v1.0.0 (Principle VI: API)
- Feature Specification: 001-qotd-nanoservice

---

## Changelog

**2025-12-01**: Initial REST API contract definition for MVP
