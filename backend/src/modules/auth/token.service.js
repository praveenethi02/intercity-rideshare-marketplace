const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const env = require('../../config/env');

const ISSUER = 'intercity-rideshare';
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function signAccessToken(userId, sessionId) {
  return jwt.sign({ sid: sessionId }, env.JWT_ACCESS_SECRET, {
    algorithm: 'HS256',
    issuer: ISSUER,
    subject: userId,
    expiresIn: env.JWT_ACCESS_TTL_SECONDS,
  });
}

/** Returns { userId, sessionId }, or null if the token is invalid or expired. */
function verifyAccessToken(token) {
  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET, {
      algorithms: ['HS256'],
      issuer: ISSUER,
    });
    return { userId: payload.sub, sessionId: payload.sid };
  } catch {
    return null;
  }
}

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/** Refresh tokens are "<sessionId>.<random>". Only the SHA-256 hash is stored. */
function generateRefreshToken(sessionId) {
  const token = `${sessionId}.${crypto.randomBytes(32).toString('base64url')}`;
  return { token, hash: hashRefreshToken(token) };
}

/** Returns the session id inside a refresh token, or null if it is malformed. */
function parseRefreshToken(token) {
  const sessionId = String(token).split('.')[0];
  return UUID_PATTERN.test(sessionId) ? sessionId : null;
}

function hashesMatch(a, b) {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

module.exports = {
  signAccessToken,
  verifyAccessToken,
  hashRefreshToken,
  generateRefreshToken,
  parseRefreshToken,
  hashesMatch,
};
