// Runs before each test file, before any application module reads the environment.
// These values exist only for tests. The database is an in-process PostgreSQL (see test-db.js).
Object.assign(process.env, {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgres://unused-in-tests',
  JWT_ACCESS_SECRET: 'test-only-jwt-secret-0123456789abcdef',
  OTP_HMAC_SECRET: 'test-only-otp-secret-0123456789abcdef',
  BCRYPT_ROUNDS: '4',
  RATE_LIMIT_ENABLED: process.env.RATE_LIMIT_ENABLED || 'false',
});
