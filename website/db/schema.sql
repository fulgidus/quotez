-- Quotes table for backoffice CRUD
CREATE TABLE IF NOT EXISTS quotes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  text TEXT NOT NULL,
  author TEXT DEFAULT '',
  source TEXT DEFAULT '',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Settings table (key-value store) for backoffice configuration
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT DEFAULT '',
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Default settings (idempotent insertion via INSERT OR IGNORE)
INSERT OR IGNORE INTO settings (key, value, description) VALUES
  ('display_mode', 'fullscreen', 'Quote display mode: fullscreen|minimal|card|terminal'),
  ('backdrop_source', 'gradient', 'Backdrop source: gradient|unsplash|upload|pattern'),
  ('qotd_host', 'localhost', 'QOTD service hostname'),
  ('qotd_port', '8017', 'QOTD service TCP port'),
  ('unsplash_api_key', '', 'Unsplash API key for backdrop images'),
  ('site_title', 'Quote of the Day', 'Website title'),
  ('refresh_interval', '0', 'Auto-refresh interval in seconds (0=disabled)');
