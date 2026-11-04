const db = require('../src/db');
const { runMigrations } = require('../src/db/migrate');

runMigrations()
  .then((applied) => {
    console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'Database is up to date');
  })
  .catch((error) => {
    console.error('Migration failed:', error.message);
    process.exitCode = 1;
  })
  .finally(() => db.close());
