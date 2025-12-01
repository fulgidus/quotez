# quotez
A tiny Zig nanoservice implementing the Quote of the Day (RFC 865) protocol over TCP and UDP. Loads, normalizes, and deduplicates quotes from local files (txt/csv/json/toml/yaml), polls for changes, and ships as a fully static binary in a minimal scratch container
