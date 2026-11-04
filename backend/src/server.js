const env = require('./config/env');
const db = require('./db');
const createApp = require('./app');

const server = createApp().listen(env.PORT, () => {
  console.log(`API listening on port ${env.PORT} (${env.NODE_ENV})`);
});

function shutdown() {
  server.close(() => {
    db.close().finally(() => process.exit(0));
  });
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
