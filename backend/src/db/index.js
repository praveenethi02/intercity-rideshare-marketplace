const { Pool } = require('pg');
const env = require('../config/env');

let driver = null;

function createPgDriver(connectionString) {
  const pool = new Pool({ connectionString });

  return {
    query: (text, params) => pool.query(text, params),
    exec: (text) => pool.query(text),
    async transaction(work) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const result = await work({
          query: (text, params) => client.query(text, params),
          exec: (text) => client.query(text),
        });
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },
    close: () => pool.end(),
  };
}

function getDb() {
  if (!driver) {
    driver = createPgDriver(env.DATABASE_URL);
  }
  return driver;
}

/** Replaces the database driver. Used by tests to run against an in-process PostgreSQL. */
function setDb(nextDriver) {
  driver = nextDriver;
}

module.exports = {
  query: (text, params) => getDb().query(text, params),
  exec: (text) => getDb().exec(text),
  transaction: (work) => getDb().transaction(work),
  close: () => (driver ? driver.close() : Promise.resolve()),
  setDb,
};
