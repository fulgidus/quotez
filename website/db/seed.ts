import { Database } from 'bun:sqlite';
import { resolve } from 'path';

// Get database path from environment or use default
const dbPath = process.env.DATABASE_PATH || './data/quotez.db';

// Open database connection
const db = new Database(dbPath);

// Sample quotes for seeding
const sampleQuotes = [
  {
    text: "The only way to do great work is to love what you do.",
    author: "Steve Jobs",
    source: "Stanford Commencement Speech"
  },
  {
    text: "Innovation distinguishes between a leader and a follower.",
    author: "Steve Jobs",
    source: "Business Week"
  },
  {
    text: "Life is what happens when you're busy making other plans.",
    author: "John Lennon",
    source: "Beautiful Boy"
  },
  {
    text: "The future belongs to those who believe in the beauty of their dreams.",
    author: "Eleanor Roosevelt",
    source: "Speeches"
  },
  {
    text: "It is during our darkest moments that we must focus to see the light.",
    author: "Aristotle",
    source: "Philosophy"
  },
  {
    text: "The only impossible journey is the one you never begin.",
    author: "Tony Robbins",
    source: "Self-Help"
  },
  {
    text: "Success is not final, failure is not fatal: it is the courage to continue that counts.",
    author: "Winston Churchill",
    source: "Speeches"
  },
  {
    text: "Believe you can and you're halfway there.",
    author: "Theodore Roosevelt",
    source: "Motivational"
  }
];

try {
  const insertStmt = db.prepare(
    `INSERT INTO quotes (text, author, source) VALUES (?, ?, ?)`
  );

  // Begin transaction for bulk insert
  db.exec('BEGIN TRANSACTION');
  
  for (const quote of sampleQuotes) {
    insertStmt.run(quote.text, quote.author, quote.source);
  }

  db.exec('COMMIT');
  console.log(`✓ Seeded ${sampleQuotes.length} quotes into ${dbPath}`);
  process.exit(0);
} catch (error) {
  db.exec('ROLLBACK');
  console.error(`✗ Seed failed: ${error.message}`);
  process.exit(1);
} finally {
  db.close();
}
