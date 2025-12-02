# Quickstart Guide

**Feature**: 001-qotd-nanoservice  
**Created**: 2025-12-01  
**Status**: Complete

## Overview

This guide provides step-by-step instructions for deploying and using quotez, the QOTD (RFC 865) nanoservice. It covers Docker deployment, local development, configuration, and basic usage.

---

## Prerequisites

### Docker Deployment (Recommended)

- Docker 20.10+ or compatible container runtime (Podman, containerd)
- Linux x86_64 or ARM64 host
- Port 17 available (TCP/UDP) or use custom ports

### Local Development

- Zig 0.13.0 compiler
- Linux operating system (musl or glibc)
- Build tools: `git`, `make` (optional)

---

## Quick Start (Docker)

### 1. Pull the Image

```bash
docker pull ghcr.io/yourorg/quotez:latest
```

### 2. Create Quote Files

```bash
mkdir -p ~/quotes
cat > ~/quotes/wisdom.txt <<EOF
The only way to do great work is to love what you do.
Innovation distinguishes between a leader and a follower.
Stay hungry, stay foolish.
EOF
```

### 3. Create Configuration

```bash
cat > ~/quotez.toml <<EOF
[server]
host = "0.0.0.0"
tcp_port = 17
udp_port = 17

[quotes]
directories = ["/data/quotes"]
mode = "random"

[polling]
interval_seconds = 60
EOF
```

### 4. Run Container

**Standard Ports (requires root/privileged)**:
```bash
docker run -d \
  --name quotez \
  -p 17:17/tcp \
  -p 17:17/udp \
  -v ~/quotes:/data/quotes:ro \
  -v ~/quotez.toml:/quotez.toml:ro \
  ghcr.io/yourorg/quotez:latest
```

**Non-Privileged Ports**:
```bash
# Update quotez.toml to use ports 8017 instead of 17
docker run -d \
  --name quotez \
  -p 8017:8017/tcp \
  -p 8017:8017/udp \
  -v ~/quotes:/data/quotes:ro \
  -v ~/quotez.toml:/quotez.toml:ro \
  ghcr.io/yourorg/quotez:latest
```

### 5. Test the Service

**TCP**:
```bash
# Using telnet
telnet localhost 17

# Using netcat
nc localhost 17

# Using curl (TCP)
curl telnet://localhost:17
```

**UDP**:
```bash
# Using netcat
echo "" | nc -u localhost 17

# Using ncat
ncat -u localhost 17
```

**Expected Output**:
```
The only way to do great work is to love what you do.
```

---

## Configuration

### Minimal Configuration

The minimal valid `quotez.toml`:

```toml
[quotes]
directories = ["/data/quotes"]
```

All other settings use defaults:
- Host: `0.0.0.0` (all interfaces)
- TCP Port: `17`
- UDP Port: `17`
- Selection Mode: `random`
- Polling Interval: `60` seconds

### Full Configuration Example

```toml
[server]
# Bind address (0.0.0.0 = all IPv4 interfaces)
host = "0.0.0.0"

# Standard QOTD port (requires root on Linux)
tcp_port = 17
udp_port = 17

[quotes]
# List of directories to scan for quote files
directories = [
    "/data/quotes",
    "/data/custom-quotes"
]

# Selection mode: random | sequential | random-no-repeat | shuffle-cycle
mode = "shuffle-cycle"

[polling]
# How often to check for file changes (seconds)
interval_seconds = 120
```

### Selection Modes

- **`random`** (default): Select any quote randomly (may repeat immediately)
- **`sequential`**: Serve quotes in order, wrap to beginning
- **`random-no-repeat`**: Random selection without repeats until all served
- **`shuffle-cycle`**: Shuffle list, serve in order, reshuffle when exhausted

---

## Quote File Formats

quotez supports 5 file formats with automatic detection:

### 1. Plaintext (`.txt`)

```
Quote one
Quote two
Quote three
```

### 2. JSON (`.json`)

```json
[
  "First quote",
  "Second quote"
]
```

Or with metadata:

```json
[
  {
    "quote": "Be yourself; everyone else is already taken.",
    "author": "Oscar Wilde"
  }
]
```

### 3. CSV (`.csv`)

```csv
quote,author
"Success is not final.","Winston Churchill"
"It always seems impossible until it's done.","Nelson Mandela"
```

### 4. TOML (`.toml`)

```toml
quotes = [
    "The purpose of our lives is to be happy.",
    "Life is really simple."
]
```

### 5. YAML (`.yaml` or `.yml`)

```yaml
---
- "The best revenge is massive success."
- "I have not failed. I've just found 10,000 ways that won't work."
```

**Note**: Author/metadata fields are ignored. Only quote text is extracted.

---

## Deployment Scenarios

### Scenario 1: Local Network QOTD Server

**Use Case**: Provide quotes to terminal users on a LAN.

**Configuration** (`quotez.toml`):
```toml
[server]
host = "0.0.0.0"  # Listen on all interfaces
tcp_port = 17
udp_port = 17

[quotes]
directories = ["/data/quotes"]
mode = "random"

[polling]
interval_seconds = 300  # Check every 5 minutes
```

**Docker Command**:
```bash
docker run -d \
  --name quotez \
  --network host \
  -v /opt/quotes:/data/quotes:ro \
  -v /etc/quotez.toml:/quotez.toml:ro \
  ghcr.io/yourorg/quotez:latest
```

**Firewall** (if needed):
```bash
sudo ufw allow 17/tcp
sudo ufw allow 17/udp
```

---

### Scenario 2: Development/Testing

**Use Case**: Test quote parsing and selection locally.

**Configuration** (`quotez-dev.toml`):
```toml
[server]
host = "127.0.0.1"  # Localhost only
tcp_port = 8017     # Non-privileged port
udp_port = 8017

[quotes]
directories = ["./quotes"]  # Relative path
mode = "sequential"         # Predictable order for testing

[polling]
interval_seconds = 10  # Fast polling for development
```

**Run Locally** (no Docker):
```bash
zig build -Doptimize=Debug
./zig-out/bin/quotez --config quotez-dev.toml
```

**Test**:
```bash
# Terminal 1: Run service
./zig-out/bin/quotez

# Terminal 2: Test with nc
nc localhost 8017
```

---

### Scenario 3: Kubernetes Deployment

**Use Case**: Deploy as a DaemonSet or Deployment in k8s cluster.

**ConfigMap** (`quotez-config.yaml`):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: quotez-config
data:
  quotez.toml: |
    [server]
    host = "0.0.0.0"
    tcp_port = 17
    udp_port = 17
    
    [quotes]
    directories = ["/data/quotes"]
    mode = "shuffle-cycle"
    
    [polling]
    interval_seconds = 120
```

**Deployment** (`quotez-deployment.yaml`):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quotez
spec:
  replicas: 2
  selector:
    matchLabels:
      app: quotez
  template:
    metadata:
      labels:
        app: quotez
    spec:
      containers:
      - name: quotez
        image: ghcr.io/yourorg/quotez:latest
        ports:
        - containerPort: 17
          protocol: TCP
        - containerPort: 17
          protocol: UDP
        volumeMounts:
        - name: config
          mountPath: /quotez.toml
          subPath: quotez.toml
        - name: quotes
          mountPath: /data/quotes
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: true
      volumes:
      - name: config
        configMap:
          name: quotez-config
      - name: quotes
        configMap:
          name: quotez-quotes  # Or PersistentVolume for dynamic updates
```

**Service** (`quotez-service.yaml`):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: quotez
spec:
  selector:
    app: quotez
  ports:
  - name: tcp
    port: 17
    protocol: TCP
  - name: udp
    port: 17
    protocol: UDP
  type: LoadBalancer  # Or ClusterIP/NodePort
```

**Deploy**:
```bash
kubectl apply -f quotez-config.yaml
kubectl apply -f quotez-deployment.yaml
kubectl apply -f quotez-service.yaml
```

---

## Monitoring & Logs

### View Logs

**Docker**:
```bash
docker logs quotez
```

**Kubernetes**:
```bash
kubectl logs -l app=quotez
```

### Expected Log Output

**Startup**:
```
[2025-12-01T12:34:56Z] INFO service_start version=1.0.0
[2025-12-01T12:34:56Z] INFO config_loaded tcp_port=17 udp_port=17 directories=1 mode=random interval=60
[2025-12-01T12:34:57Z] INFO quote_store_built files=5 quotes=150 duplicates_removed=8
```

**Reload Event**:
```
[2025-12-01T13:00:00Z] INFO file_change_detected directory=/data/quotes
[2025-12-01T13:00:01Z] INFO quote_store_rebuilt files=6 quotes=175 duplicates_removed=10
```

**Warnings**:
```
[2025-12-01T12:34:57Z] WARN empty_quote_store directories=1
[2025-12-01T12:34:57Z] WARN file_parse_error path=/data/quotes/bad.json reason="unexpected token"
```

**Errors**:
```
[2025-12-01T12:34:56Z] ERROR config_error reason="missing required field: directories"
[2025-12-01T12:34:56Z] ERROR bind_error host=0.0.0.0 port=17 reason="Address already in use"
```

---

## Troubleshooting

### Issue: "Address already in use"

**Cause**: Another service is using port 17.

**Solution**:
```bash
# Check what's using the port
sudo lsof -i :17

# Use a different port in quotez.toml
[server]
tcp_port = 8017
udp_port = 8017
```

---

### Issue: "Permission denied" binding to port 17

**Cause**: Ports < 1024 require root privileges on Linux.

**Solution 1**: Run with elevated privileges (Docker)
```bash
docker run --cap-add=NET_BIND_SERVICE ...
```

**Solution 2**: Use non-privileged ports (8017)
```toml
[server]
tcp_port = 8017
udp_port = 8017
```

**Solution 3**: Set CAP_NET_BIND_SERVICE capability (native binary)
```bash
sudo setcap 'cap_net_bind_service=+ep' ./zig-out/bin/quotez
./zig-out/bin/quotez  # No sudo needed
```

---

### Issue: Empty quote store warning

**Cause**: No valid quotes found in directories.

**Solution**:
```bash
# Check directory exists and contains files
ls -la /data/quotes

# Verify file permissions
cat /data/quotes/quotes.txt

# Check logs for parsing errors
docker logs quotez | grep ERROR
```

---

### Issue: Quote files not updating

**Cause**: Polling interval hasn't elapsed or change detection failed.

**Solution**:
```bash
# Check polling interval in config
grep interval quotez.toml

# Wait for next poll cycle (default: 60 seconds)
# Or restart service to force reload
docker restart quotez
```

---

### Issue: UDP responses not received

**Cause**: UDP is stateless; responses may be dropped by network.

**Solution**:
```bash
# Use tcpdump to verify responses are sent
sudo tcpdump -i any -n udp port 17

# Try TCP instead (more reliable)
nc localhost 17
```

---

## Performance Tuning

### For Large Quote Collections (10k+ quotes)

**Increase polling interval** to reduce I/O:
```toml
[polling]
interval_seconds = 300  # 5 minutes
```

**Use `shuffle-cycle` mode** for balanced distribution:
```toml
[quotes]
mode = "shuffle-cycle"
```

### For High Request Rates

**Use TCP** for better concurrency handling.

**Deploy multiple instances** behind a load balancer.

**Monitor logs** for connection errors:
```bash
docker logs quotez | grep ERROR
```

---

## Security Best Practices

1. **Run as non-root user**:
   ```dockerfile
   USER 1000:1000
   ```

2. **Mount quote directories read-only**:
   ```bash
   -v ~/quotes:/data/quotes:ro
   ```

3. **Use firewall rules** to limit access:
   ```bash
   sudo ufw allow from 192.168.1.0/24 to any port 17
   ```

4. **Enable rate limiting** at network level (not in quotez MVP).

5. **Monitor logs** for abuse patterns.

---

## Building from Source

### Install Zig 0.13.0

```bash
# Download from https://ziglang.org/download/
wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
tar xf zig-linux-x86_64-0.13.0.tar.xz
export PATH=$PWD/zig-linux-x86_64-0.13.0:$PATH
```

### Clone Repository

```bash
git clone https://github.com/yourorg/quotez.git
cd quotez
```

### Build

**Development**:
```bash
zig build
./zig-out/bin/quotez
```

**Release** (static musl binary):
```bash
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
strip ./zig-out/bin/quotez  # Optional: strip symbols
```

### Run Tests

```bash
zig build test
```

### Build Docker Image

```dockerfile
# Dockerfile
FROM scratch
COPY zig-out/bin/quotez /quotez
ENTRYPOINT ["/quotez"]
```

```bash
# Build static binary
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl

# Build image
docker build -t quotez:local .

# Run
docker run -d \
  -p 17:17/tcp -p 17:17/udp \
  -v ~/quotes:/data/quotes:ro \
  -v ~/quotez.toml:/quotez.toml:ro \
  quotez:local
```

---

## API Reference

### Command-Line Arguments (Post-MVP)

**MVP**: No command-line arguments supported. Use `quotez.toml` for all configuration.

**Post-MVP**:
```bash
quotez --config /path/to/config.toml
quotez --version
quotez --help
```

### Environment Variables (Post-MVP)

**MVP**: No environment variable support.

**Post-MVP**:
```bash
QUOTEZ_TCP_PORT=8017 quotez
QUOTEZ_DIRECTORIES=/data/quotes:/opt/quotes quotez
```

---

## FAQ

**Q: Can I use quotez without Docker?**  
A: Yes, build the static binary and run directly: `./quotez`

**Q: Does quotez support IPv6?**  
A: Yes, set `host = "::"` to bind to IPv6 interfaces.

**Q: Can I reload quotes without restarting?**  
A: Yes, quotez polls for file changes every 60 seconds (configurable).

**Q: Can I reload configuration without restarting?**  
A: No, configuration changes require service restart (MVP limitation).

**Q: What happens if the quote directory is empty?**  
A: Service starts with empty store, logs warning, sends empty responses.

**Q: Can I use multiple selection modes simultaneously?**  
A: No, only one mode per service instance.

**Q: Does quotez support authentication?**  
A: No, QOTD protocol has no authentication (use firewall for access control).

**Q: What's the maximum quote length?**  
A: No hard limit in MVP. RFC 865 recommends < 512 bytes for UDP compatibility.

**Q: Can I get metrics (Prometheus, StatsD)?**  
A: Not in MVP. Post-MVP feature.

---

## Next Steps

1. **Explore Selection Modes**: Try `sequential` and `shuffle-cycle` modes
2. **Add More Quotes**: Create quote files in different formats
3. **Automate Deployment**: Use Kubernetes Helm charts or docker-compose
4. **Monitor Logs**: Set up log aggregation (ELK, Loki, etc.)
5. **Contribute**: Submit PRs with additional quotes or features

---

## References

- [RFC 865 - Quote of the Day Protocol](https://www.rfc-editor.org/rfc/rfc865.html)
- [quotez GitHub Repository](https://github.com/yourorg/quotez)
- [Zig Documentation](https://ziglang.org/documentation/0.13.0/)
- Contract Documents:
  - `contracts/qotd-protocol.md` - Protocol specification
  - `contracts/config-schema.md` - Configuration reference
  - `contracts/quote-formats.md` - File format specifications

---

## Support

- GitHub Issues: https://github.com/yourorg/quotez/issues
- Discussions: https://github.com/yourorg/quotez/discussions
- Email: quotez@yourorg.com

---

**Last Updated**: 2025-12-01  
**Version**: 1.0.0 (MVP)
