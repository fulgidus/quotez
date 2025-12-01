# quotez

A tiny Zig nanoservice implementing the Quote of the Day (RFC 865) protocol over TCP and UDP. It loads, normalizes, and deduplicates quotes from local files (txt/csv/json/toml/yaml) and serves them on demand. Ships as a static binary in a minimal scratch container.

## Features
- QOTD over TCP/UDP
- Automatic quote file parsing
- Global deduplication
- Periodic directory polling
- Static build for scratch images

## License
MIT
