const db = require('../../db');

/** Opens a review for a driver. The unique index allows one open request, so repeats do nothing. */
async function openForDriver(userId, client = db) {
  await client.query(
    `INSERT INTO verification_requests (type, subject_id) VALUES ('DRIVER', $1)
     ON CONFLICT (type, subject_id) WHERE status = 'PENDING' DO NOTHING`,
    [userId],
  );
}

async function findLatestForDriver(userId, client = db) {
  const { rows } = await client.query(
    `SELECT * FROM verification_requests
     WHERE type = 'DRIVER' AND subject_id = $1
     ORDER BY submitted_at DESC, id LIMIT 1`,
    [userId],
  );
  return rows[0] || null;
}

/** Locks the request until the transaction ends, so two admins cannot both decide it. */
async function lock(id, client) {
  const { rows } = await client.query(
    'SELECT * FROM verification_requests WHERE id = $1 FOR UPDATE',
    [id],
  );
  return rows[0] || null;
}

async function decide(id, { status, reason, adminId }, client = db) {
  const { rows } = await client.query(
    `UPDATE verification_requests
     SET status = $2, reason = $3, decided_at = now(), decided_by = $4
     WHERE id = $1 RETURNING *`,
    [id, status, reason, adminId],
  );
  return rows[0];
}

/** Returns one page of the queue, oldest first, and the total number of matches. */
async function search({ status, type, page, limit }, client = db) {
  const filter = '($1::text IS NULL OR status = $1::text) AND ($2::text IS NULL OR type = $2::text)';
  const filterParams = [status ?? null, type ?? null];

  const count = await client.query(
    `SELECT count(*)::int AS total FROM verification_requests WHERE ${filter}`,
    filterParams,
  );
  const { rows } = await client.query(
    `SELECT * FROM verification_requests WHERE ${filter}
     ORDER BY submitted_at, id
     LIMIT $3::int OFFSET $4::int`,
    [...filterParams, limit, (page - 1) * limit],
  );
  return { requests: rows, total: count.rows[0].total };
}

module.exports = { openForDriver, findLatestForDriver, lock, decide, search };
