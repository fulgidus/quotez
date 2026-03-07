import { Database } from 'bun:sqlite';
import fs from 'node:fs';
import path from 'node:path';

/**
 * Initialize the database schema by running schema.sql
 * @param db SQLite database instance
 */
export function initDb(db: Database): void {
  // Enable WAL mode for better concurrency
  db.run('PRAGMA journal_mode=WAL');
  
  // Read and execute schema.sql
  const schemaPath = path.join(import.meta.dir, '..', '..', 'db', 'schema.sql');
  const schema = fs.readFileSync(schemaPath, 'utf-8');
  
  // Split by semicolon and execute each statement
  const statements = schema.split(';').filter(stmt => stmt.trim());
  for (const stmt of statements) {
    db.run(stmt);
  }
  
  console.log('[settings] Database schema initialized');
}

/**
 * Retrieve a single setting value from the database
 * @param db SQLite database instance
 * @param key Setting key to retrieve
 * @returns Setting value as string, or null if not found
 */
export function getSetting(db: Database, key: string): string | null {
  const query = db.query<{ value: string }, [string]>(
    'SELECT value FROM settings WHERE key = ?'
  );
  const result = query.get(key);
  return result?.value ?? null;
}

/**
 * Set a setting value in the database
 * @param db SQLite database instance
 * @param key Setting key to set
 * @param value Setting value to store
 */
export function setSetting(db: Database, key: string, value: string): void {
  const query = db.query<void, [string, string]>(
    'INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, datetime("now"))'
  );
  query.run(key, value);
}

/**
 * Retrieve all settings from the database as a key-value object
 * @param db SQLite database instance
 * @returns Object mapping setting keys to their values
 */
export function getAllSettings(db: Database): Record<string, string> {
  const query = db.query<{ key: string; value: string }, []>(
    'SELECT key, value FROM settings'
  );
  const rows = query.all();
  
  const settings: Record<string, string> = {};
  for (const row of rows) {
    settings[row.key] = row.value;
  }
  
  return settings;
}
