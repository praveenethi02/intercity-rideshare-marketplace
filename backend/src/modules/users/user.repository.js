const db = require('../../db');

async function findById(id, client = db) {
  const { rows } = await client.query('SELECT * FROM users WHERE id = $1', [id]);
  return rows[0] || null;
}

async function findByPhone(phone, client = db) {
  const { rows } = await client.query('SELECT * FROM users WHERE phone = $1', [phone]);
  return rows[0] || null;
}

/** The display name stored in full_name: "first last", or just the first name. */
const joinName = (firstName, lastName) => [firstName, lastName].filter(Boolean).join(' ');

async function create({ firstName, lastName = '', phone, email, passwordHash, role, status }, client = db) {
  const { rows } = await client.query(
    `INSERT INTO users (first_name, last_name, full_name, phone, email, password_hash, role, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [firstName, lastName, joinName(firstName, lastName), phone, email ?? null, passwordHash, role, status],
  );
  return rows[0];
}

/** Replaces the details of a registration that was never verified. */
async function updatePendingRegistration(
  id,
  { firstName, lastName, email, passwordHash, role },
  client = db,
) {
  const { rows } = await client.query(
    `UPDATE users
     SET first_name = $2, last_name = $3, full_name = $4, email = $5, password_hash = $6, role = $7,
         updated_at = now()
     WHERE id = $1 AND status = 'PENDING_VERIFICATION'
     RETURNING *`,
    [id, firstName, lastName, joinName(firstName, lastName), email ?? null, passwordHash, role],
  );
  return rows[0] || null;
}

async function markPhoneVerified(id, client = db) {
  const { rows } = await client.query(
    `UPDATE users
     SET status = 'ACTIVE', phone_verified_at = now(), updated_at = now()
     WHERE id = $1 AND status = 'PENDING_VERIFICATION'
     RETURNING *`,
    [id],
  );
  return rows[0] || null;
}

async function updatePassword(id, passwordHash, client = db) {
  await client.query('UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1', [
    id,
    passwordHash,
  ]);
}

/**
 * Updates only the fields provided. A null value clears an optional field.
 * full_name is rebuilt from the first and last names after either one changes.
 */
async function updateProfile(id, { firstName, lastName, email, avatarUrl }, client = db) {
  const { rows } = await client.query(
    `WITH names AS (
       SELECT CASE WHEN $2 THEN $3 ELSE first_name END AS first_name,
              CASE WHEN $4 THEN $5 ELSE last_name END AS last_name
       FROM users WHERE id = $1
     )
     UPDATE users
     SET first_name = names.first_name,
         last_name = names.last_name,
         full_name = CASE WHEN $2 OR $4
                          THEN btrim(names.first_name || ' ' || names.last_name)
                          ELSE users.full_name END,
         email = CASE WHEN $6 THEN $7 ELSE email END,
         avatar_url = CASE WHEN $8 THEN $9 ELSE avatar_url END,
         updated_at = now()
     FROM names
     WHERE users.id = $1
     RETURNING users.*`,
    [
      id,
      firstName !== undefined,
      firstName ?? null,
      lastName !== undefined,
      lastName ?? null,
      email !== undefined,
      email ?? null,
      avatarUrl !== undefined,
      avatarUrl ?? null,
    ],
  );
  return rows[0] || null;
}

async function updateRole(id, role, client = db) {
  const { rows } = await client.query(
    'UPDATE users SET role = $2, updated_at = now() WHERE id = $1 RETURNING *',
    [id, role],
  );
  return rows[0] || null;
}

/** Moves a user from one status to another. Returns null if they are no longer in fromStatus. */
async function changeStatus(id, fromStatus, toStatus, client = db) {
  const { rows } = await client.query(
    `UPDATE users SET status = $3, updated_at = now()
     WHERE id = $1 AND status = $2
     RETURNING *`,
    [id, fromStatus, toStatus],
  );
  return rows[0] || null;
}

/** Returns one page of users, newest first, and the total number of matches. */
async function search({ role, status, search: text, page, limit }, client = db) {
  // Escape LIKE wildcards so that a search for "100%" is taken literally.
  const pattern = text ? `%${text.replace(/[\\%_]/g, '\\$&')}%` : null;
  const filter = `
    ($1::user_role IS NULL OR role = $1::user_role)
    AND ($2::user_status IS NULL OR status = $2::user_status)
    AND ($3::text IS NULL OR full_name ILIKE $3::text OR phone ILIKE $3::text OR email ILIKE $3::text)`;
  const filterParams = [role ?? null, status ?? null, pattern];

  const count = await client.query(
    `SELECT count(*)::int AS total FROM users WHERE ${filter}`,
    filterParams,
  );
  const { rows } = await client.query(
    `SELECT * FROM users WHERE ${filter}
     ORDER BY created_at DESC, id
     LIMIT $4::int OFFSET $5::int`,
    [...filterParams, limit, (page - 1) * limit],
  );

  return { users: rows, total: count.rows[0].total };
}

/** Fields safe to send to API clients. Never includes the password hash. */
function toPublicUser(user) {
  return {
    id: user.id,
    firstName: user.first_name,
    lastName: user.last_name,
    fullName: user.full_name,
    phone: user.phone,
    email: user.email,
    role: user.role,
    status: user.status,
    avatarUrl: user.avatar_url,
    phoneVerifiedAt: user.phone_verified_at,
    createdAt: user.created_at,
    updatedAt: user.updated_at,
  };
}

module.exports = {
  findById,
  findByPhone,
  create,
  updatePendingRegistration,
  markPhoneVerified,
  updatePassword,
  updateProfile,
  updateRole,
  changeStatus,
  search,
  toPublicUser,
};
