const db = require('../../db');
const env = require('../../config/env');

async function create({ id, userId, refreshTokenHash }, client = db) {
  await client.query(
    `INSERT INTO sessions (id, user_id, refresh_token_hash, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(days => $4::int))`,
    [id, userId, refreshTokenHash, env.REFRESH_TOKEN_TTL_DAYS],
  );
}

/** Returns the session only if it has not been revoked and has not expired. */
async function findLive(id, client = db) {
  const { rows } = await client.query(
    'SELECT * FROM sessions WHERE id = $1 AND revoked_at IS NULL AND expires_at > now()',
    [id],
  );
  return rows[0] || null;
}

/** Swaps the refresh token. Returns false if another request already used the old one. */
async function rotate(id, oldHash, newHash, client = db) {
  const { rows } = await client.query(
    `UPDATE sessions
     SET refresh_token_hash = $3,
         last_used_at = now(),
         expires_at = now() + make_interval(days => $4::int)
     WHERE id = $1 AND refresh_token_hash = $2 AND revoked_at IS NULL
     RETURNING id`,
    [id, oldHash, newHash, env.REFRESH_TOKEN_TTL_DAYS],
  );
  return rows.length === 1;
}

async function revoke(id, client = db) {
  await client.query(
    'UPDATE sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL',
    [id],
  );
}

/** Revokes all of a user's sessions, optionally keeping the current one. */
async function revokeAllForUser(userId, { exceptSessionId = null } = {}, client = db) {
  await client.query(
    `UPDATE sessions SET revoked_at = now()
     WHERE user_id = $1 AND revoked_at IS NULL AND ($2::uuid IS NULL OR id <> $2::uuid)`,
    [userId, exceptSessionId],
  );
}

module.exports = { create, findLive, rotate, revoke, revokeAllForUser };
