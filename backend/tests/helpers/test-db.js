const { PGlite } = require('@electric-sql/pglite');
const db = require('../../src/db');
const { runMigrations } = require('../../src/db/migrate');

function adapt(connection) {
  return {
    async query(text, params) {
      const result = await connection.query(text, params);
      return { rows: result.rows, rowCount: result.affectedRows ?? result.rows.length };
    },
    exec: (text) => connection.exec(text),
  };
}

/** Starts an in-process PostgreSQL, points the app at it and applies all migrations. */
async function startTestDb() {
  const pglite = new PGlite();
  await pglite.waitReady;

  db.setDb({
    ...adapt(pglite),
    transaction: (work) => pglite.transaction((tx) => work(adapt(tx))),
    close: () => pglite.close(),
  });

  await runMigrations();
}

/** Empties every application table between tests. */
async function resetTestDb() {
  const { rows } = await db.query(
    `SELECT tablename FROM pg_tables
     WHERE schemaname = 'public' AND tablename <> 'schema_migrations'`,
  );
  if (rows.length > 0) {
    const tables = rows.map((row) => `"${row.tablename}"`).join(', ');
    await db.exec(`TRUNCATE ${tables} CASCADE`);
  }
}

module.exports = { startTestDb, resetTestDb, stopTestDb: () => db.close() };
