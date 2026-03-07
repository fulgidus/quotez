import { Database } from 'bun:sqlite';

/**
 * Retrieve a single setting value from the database
 * @param db SQLite database instance
 * @param key Setting key to retrieve
 * @returns Setting value as string, or empty string if not found
 */
export function getSetting(db: Database, key: string): string {
  const query = db.query<{ value: string }, [string]>(
    'SELECT value FROM settings WHERE key = ?'
  );
  const result = query.get(key);
  return result?.value ?? '';
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
