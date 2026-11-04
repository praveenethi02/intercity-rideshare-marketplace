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

module.exports = { findById, findByPhone, create, toPublicUser };
