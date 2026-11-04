const db = require('../../db');

async function findById(id, client = db) {
  const { rows } = await client.query('SELECT * FROM users WHERE id = $1', [id]);
  return rows[0] || null;
}

async function findByPhone(phone, client = db) {
  const { rows } = await client.query('SELECT * FROM users WHERE phone = $1', [phone]);
  return rows[0] || null;
}

async function create({ fullName, phone, email, passwordHash, role, status }, client = db) {
  const { rows } = await client.query(
    `INSERT INTO users (full_name, phone, email, password_hash, role, status)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`,
    [fullName, phone, email ?? null, passwordHash, role, status],
  );
  return rows[0];
}

/** Replaces the details of a registration that was never verified. */
async function updatePendingRegistration(id, { fullName, email, passwordHash, role }, client = db) {
  const { rows } = await client.query(
    `UPDATE users
     SET full_name = $2, email = $3, password_hash = $4, role = $5, updated_at = now()
     WHERE id = $1 AND status = 'PENDING_VERIFICATION'
     RETURNING *`,
    [id, fullName, email ?? null, passwordHash, role],
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

/** Updates only the fields provided. A null value clears an optional field. */
async function updateProfile(id, { fullName, email, avatarUrl }, client = db) {
  const { rows } = await client.query(
    `UPDATE users
     SET full_name = CASE WHEN $2 THEN $3 ELSE full_name END,
         email = CASE WHEN $4 THEN $5 ELSE email END,
         avatar_url = CASE WHEN $6 THEN $7 ELSE avatar_url END,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      id,
      fullName !== undefined,
      fullName ?? null,
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

/** Fields safe to send to API clients. Never includes the password hash. */
function toPublicUser(user) {
  return {
    id: user.id,
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
  toPublicUser,
};
