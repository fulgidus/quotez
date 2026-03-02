import { Database } from 'bun:sqlite';
import { resolve } from 'path';

// Get database path from environment or use default
const dbPath = process.env.DATABASE_PATH || './data/quotez.db';

// Ensure data directory exists
import { mkdir } from 'fs/promises';
await mkdir('./data', { recursive: true }).catch(() => {});

// Open database connection
const db = new Database(dbPath);

// Read and execute schema
const schemaPath = resolve(import.meta.dir, './schema.sql');
const schema = await Bun.file(schemaPath).text();

try {
  db.exec(schema);
  console.log(`✓ Migration complete: ${dbPath}`);
  process.exit(0);
} catch (error) {
  console.error(`✗ Migration failed: ${error.message}`);
  process.exit(1);
} finally {
  db.close();
}
