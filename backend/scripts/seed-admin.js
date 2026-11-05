require('../src/config/env');
const db = require('../src/db');
const seedAdmin = require('../src/db/seed-admin');

seedAdmin()
  .then((created) => {
    console.log(created ? 'Admin account created' : 'That phone number already exists: no change');
  })
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(() => db.close());
