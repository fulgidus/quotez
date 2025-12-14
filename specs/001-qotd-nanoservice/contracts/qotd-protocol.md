# QOTD Protocol Contract

**Feature**: 001-qotd-nanoservice  
**RFC**: 865  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This document defines the implementation contract for RFC 865 Quote of the Day protocol as implemented by quotez. It specifies exact TCP and UDP behaviors, message formats, and compliance requirements.

## RFC 865 Summary

**Protocol**: Quote of the Day (QOTD)  
**Purpose**: Send a short message (quote) to a client upon connection  
**Transports**: TCP and UDP  
**Default Port**: 17 (configurable in quotez)  
**Standard**: [RFC 865](https://www.rfc-editor.org/rfc/rfc865.html)

**Key Requirements from RFC 865**:
- TCP: Server sends quote and closes connection immediately
- UDP: Server sends quote datagram in response to any incoming datagram
- Quote length: "short" (RFC recommends < 512 characters)
- No authentication or client commands required

---

## TCP Implementation

### Connection Flow

```
Client                                Server (quotez)
  │                                        │
  ├─────── SYN ──────────────────────────►│
  │                                        │
  │◄────── SYN-ACK ────────────────────────┤
  │                                        │
  ├─────── ACK ──────────────────────────►│
  │                                        │ [Connection Established]
  │                                        │
  │                                        ├─► Select quote from store
  │                                        │
  │◄────── Quote Text + "\n" ──────────────┤
  │                                        │
  │◄────── FIN ────────────────────────────┤ [Server closes]
  │                                        │
  ├─────── ACK ──────────────────────────►│
  │                                        │
```

### Server Behavior

**1. Binding and Listening**:
- Bind to configured `host:tcp_port` (default: `0.0.0.0:17`)
- Enter listening state with reasonable backlog (128 connections)
- Set socket to non-blocking mode for event loop integration

**2. Connection Acceptance**:
- Accept incoming connection via `accept()`
- No handshake, authentication, or client message expected
- Connection is short-lived (close after sending quote)

**3. Quote Selection and Transmission**:
```zig
// Pseudocode
const quote = quote_store.next() orelse "";  // Empty if no quotes
if (quote.len > 0) {
    try conn.writeAll(quote);
    try conn.writeAll("\n");  // Newline terminator (optional per RFC, but conventional)
}
conn.close();  // Immediate close
```

**4. Message Format**:
- Content: UTF-8 encoded quote text
- Terminator: Single newline (`\n`) RECOMMENDED (not required by RFC but conventional)
- Maximum length: 512 bytes typical, no hard limit enforced in MVP
- Empty response: Connection closes immediately without sending data (when quote store is empty)

**5. Error Handling**:
- Send failure: Log error, close connection
- Client disconnect during send: Ignore, clean up connection
- Quote store empty: Close connection without sending

### Compliance Requirements

| Requirement | RFC 865 | quotez Implementation |
|-------------|---------|----------------------|
| Listen on TCP | ✅ Required | ✅ Port 17 (default, configurable) |
| Send quote on connect | ✅ Required | ✅ One quote per connection |
| Close after sending | ✅ Required | ✅ Immediate close() after write |
| No client input expected | ✅ Implicit | ✅ Server writes, ignores reads |
| Short message | ✅ Recommended | ✅ Typical < 512 bytes, no enforcement |

### Example TCP Session

**Request**:
```bash
$ telnet localhost 17
Trying 127.0.0.1...
Connected to localhost.
```

**Response**:
```
The only way to do great work is to love what you do. - Steve Jobs
Connection closed by foreign host.
```

**Wire Format** (with `\n` terminator):
```
0x54 0x68 0x65 0x20 0x6f 0x6e 0x6c 0x79 ...  "The only way..."
... 0x2e 0x0a                                 "...\n"
[FIN packet]
```

---

## UDP Implementation

### Datagram Exchange Flow

```
Client                                Server (quotez)
  │                                        │
  ├─────── Datagram (any content) ───────►│
  │                                        │ [Datagram received]
  │                                        │
  │                                        ├─► Select quote from store
  │                                        │
  │◄────── Quote Datagram ─────────────────┤
  │                                        │
```

### Server Behavior

**1. Binding**:
- Bind to configured `host:udp_port` (default: `0.0.0.0:17`)
- Set socket to non-blocking mode for event loop integration

**2. Datagram Reception**:
- Use `recvfrom()` to receive datagram from client
- **Content of client datagram is ignored** (RFC 865 specifies server doesn't process input)
- Extract client address for response

**3. Quote Selection and Reply**:
```zig
// Pseudocode
var buf: [512]u8 = undefined;
const addr = try udp_socket.recvfrom(&buf, 0);  // Receive (ignore content)

const quote = quote_store.next() orelse "";
if (quote.len > 0) {
    const message = try std.fmt.bufPrint(&buf, "{s}\n", .{quote});
    _ = try udp_socket.sendto(message, 0, addr);  // Send to client
}
// If quote store empty: No response sent (silent drop per UDP semantics)
```

**4. Message Format**:
- Content: UTF-8 encoded quote text
- Terminator: Single newline (`\n`) RECOMMENDED
- Maximum length: 512 bytes (typical UDP datagram limit for QOTD)
- Empty quote store: No response sent (silent drop)

**5. Error Handling**:
- Send failure: Log error, drop response (UDP is best-effort)
- Oversized quote (> 512 bytes): Truncate or log warning (implementation choice)
- Quote store empty: Silent drop (no response)

### Compliance Requirements

| Requirement | RFC 865 | quotez Implementation |
|-------------|---------|----------------------|
| Listen on UDP | ✅ Required | ✅ Port 17 (default, configurable) |
| Respond to any datagram | ✅ Required | ✅ Ignore content, send quote |
| Single datagram response | ✅ Required | ✅ One response per request |
| No acknowledgment | ✅ Implicit | ✅ Stateless, no handshake |

### Example UDP Session

**Request**:
```bash
$ echo "" | nc -u localhost 17
```

**Response**:
```
In the middle of difficulty lies opportunity. - Albert Einstein
```

**Wire Format**:
```
Client sends:
  UDP packet: src=<client_ip>:<random_port> dst=<server_ip>:17
  Payload: [empty or arbitrary bytes]

Server sends:
  UDP packet: src=<server_ip>:17 dst=<client_ip>:<random_port>
  Payload: "In the middle of difficulty lies opportunity. - Albert Einstein\n"
```

---

## Quote Content Constraints

### Character Encoding
- **MUST** be valid UTF-8
- Invalid UTF-8 sequences replaced with Unicode replacement character (U+FFFD) during parsing
- No specific charset declaration in protocol (UTF-8 is implicit)

### Length Limits
- **RFC Recommendation**: "short message" (< 512 characters)
- **quotez Implementation**: No hard limit enforced in MVP
- **Practical Limit**: TCP allows any length; UDP recommended < 512 bytes to fit single datagram

### Whitespace Normalization
- Leading/trailing whitespace trimmed during quote loading
- Internal whitespace preserved
- Newlines within quotes replaced with spaces (single-line response)
- Terminating `\n` added by server during transmission

### Empty Quote Store Behavior
- **TCP**: Accept connection, close immediately without sending data
- **UDP**: Receive datagram, send no response (silent drop)
- **Logging**: WARN level message on startup and each reload resulting in zero quotes

---

## Concurrent Connection Handling

### TCP Concurrency
- Single-threaded event loop with `poll()` or `epoll()`
- Connections accepted sequentially
- No artificial connection limit (bounded by OS and network stack)
- Each connection is short-lived (send quote, close immediately)

### UDP Concurrency
- Stateless by nature
- No connection tracking required
- Responses sent synchronously per received datagram
- No queueing or rate limiting in MVP

---

## Network Error Handling

### TCP Errors

| Error | Scenario | quotez Behavior |
|-------|----------|-----------------|
| ECONNRESET | Client disconnects during send | Log, clean up connection |
| EPIPE | Write to closed socket | Log, clean up connection |
| EAGAIN/EWOULDBLOCK | Non-blocking I/O | Retry or drop (MVP: log and close) |
| EMFILE | Too many open files | Log error, reject connection |

### UDP Errors

| Error | Scenario | quotez Behavior |
|-------|----------|-----------------|
| EMSGSIZE | Datagram too large | Log warning, truncate or drop |
| EAGAIN/EWOULDBLOCK | Non-blocking I/O | Skip response (best-effort) |
| ECONNREFUSED | Client port unreachable | Ignore (UDP is stateless) |

---

## Performance Characteristics

### Response Times
- **TCP**: < 10ms from connection establishment to data sent (measured server-side)
- **UDP**: < 10ms from datagram receipt to response sent

### Throughput
- **TCP**: Limited by connection rate (accept loop speed)
- **UDP**: Limited by datagram processing rate
- **Expected Load**: 10-100 requests/minute typical for QOTD service
- **Stress Test Target**: 100 concurrent TCP connections without refusal

---

## Security Considerations

### Denial of Service (DoS)
- **TCP SYN Flood**: Rely on OS-level SYN cookies and firewall rules
- **UDP Amplification**: Quote length limited to prevent amplification attacks (MVP: no strict limit, post-MVP consideration)
- **Connection Exhaustion**: No rate limiting in MVP; assume firewall/iptables protection

### Information Disclosure
- **Quotes are public**: No authentication or authorization in MVP
- **No user input processed**: Eliminates injection attacks
- **No error messages sent to clients**: Reduces information leakage

### Recommendations for Deployment
- Run behind firewall with rate limiting
- Use non-root user (principle of least privilege)
- Monitor connection rates and log anomalies
- Consider fail2ban or equivalent for repeated abuse

---

## Testing & Validation

### Protocol Compliance Tests

**TCP Compliance**:
```bash
# Test 1: Basic connection and quote receipt
echo "" | nc localhost 17 | wc -l  # Should be >= 1 (quote + newline)

# Test 2: Connection closes after quote
(echo "" && sleep 1) | nc localhost 17  # Should terminate immediately

# Test 3: Multiple sequential connections
for i in {1..10}; do echo "" | nc localhost 17; done  # All succeed
```

**UDP Compliance**:
```bash
# Test 1: Basic datagram exchange
echo "test" | nc -u localhost 17  # Should receive quote

# Test 2: Empty datagram
echo "" | nc -u -w 1 localhost 17  # Should still receive quote

# Test 3: Arbitrary content ignored
echo "ignored data" | nc -u localhost 17  # Response unrelated to input
```

### Edge Case Tests

| Test Case | Expected Behavior |
|-----------|-------------------|
| Empty quote store (TCP) | Connection closes immediately, no data sent |
| Empty quote store (UDP) | No response sent (silent drop) |
| Quote > 512 bytes (TCP) | Full quote sent (no truncation) |
| Quote > 512 bytes (UDP) | Quote sent (may fragment or log warning) |
| Client closes during TCP send | Server logs error, cleans up |
| UDP response fails | Server logs error, continues |

---

## RFC 865 Compliance Summary

✅ **Full Compliance Achieved**:
- TCP server sends quote and closes connection immediately
- UDP server responds to any datagram with quote
- Both protocols listen on port 17 (default, configurable)
- No client authentication or input processing
- Short messages (typical < 512 bytes)

🔹 **Implementation-Specific Choices**:
- Newline terminator added (conventional, not required by RFC)
- UTF-8 encoding (RFC doesn't specify charset)
- Empty quote store behavior (silent drop/close, RFC doesn't address)
- Non-blocking I/O with event loop (RFC allows any implementation)

---

## References

- [RFC 865 - Quote of the Day Protocol](https://www.rfc-editor.org/rfc/rfc865.html)
- [RFC 768 - User Datagram Protocol (UDP)](https://www.rfc-editor.org/rfc/rfc768.html)
- [RFC 793 - Transmission Control Protocol (TCP)](https://www.rfc-editor.org/rfc/rfc793.html)
- IANA Port Registry: Port 17 assigned to qotd (TCP/UDP)

---

## Changelog

**2025-12-01**: Initial protocol contract based on RFC 865 and quotez specification
