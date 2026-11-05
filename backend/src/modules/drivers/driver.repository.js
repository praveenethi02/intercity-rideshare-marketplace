const db = require('../../db');

// The casts return DATE as plain text (no time zone shift) and NUMERIC as a number.
// The NIC and bank details are deliberately left out, so they can never reach a response.
const PROFILE_COLUMNS = `user_id, license_number, license_expiry::text AS license_expiry,
  date_of_birth::text AS date_of_birth, address, emergency_contact_name, emergency_contact_phone,
  verification_status, rejection_reason, verified_at, verified_by, account_status,
  rating_avg::float8 AS rating_avg, rating_count`;

async function findByUserId(userId, client = db) {
  const { rows } = await client.query(
    `SELECT ${PROFILE_COLUMNS} FROM driver_profiles WHERE user_id = $1`,
    [userId],
  );
  return rows[0] || null;
}

/** Locks the profile until the transaction ends, so concurrent changes run one at a time. */
async function lock(userId, client) {
  const { rows } = await client.query(
    `SELECT ${PROFILE_COLUMNS} FROM driver_profiles WHERE user_id = $1 FOR UPDATE`,
    [userId],
  );
  return rows[0] || null;
}

async function create(userId, details, client = db) {
  const { rows } = await client.query(
    `INSERT INTO driver_profiles
       (user_id, license_number, license_expiry, nic_number, date_of_birth, address,
        emergency_contact_name, emergency_contact_phone)
     VALUES ($1, $2, $3::date, $4, $5::date, $6, $7, $8)
     RETURNING ${PROFILE_COLUMNS}`,
    [
      userId,
      details.licenceNumber,
      details.licenceExpiry,
      details.nic,
      details.dateOfBirth ?? null,
      details.address ?? null,
      details.emergencyContactName ?? null,
      details.emergencyContactPhone ?? null,
    ],
  );
  return rows[0];
}

async function update(userId, changes, client = db) {
  const { rows } = await client.query(
    `UPDATE driver_profiles SET
       license_number = COALESCE($2, license_number),
       license_expiry = COALESCE($3::date, license_expiry),
       bank_account = COALESCE($4::jsonb, bank_account),
       address = COALESCE($5, address),
       emergency_contact_name = COALESCE($6, emergency_contact_name),
       emergency_contact_phone = COALESCE($7, emergency_contact_phone),
       updated_at = now()
     WHERE user_id = $1
     RETURNING ${PROFILE_COLUMNS}`,
    [
      userId,
      changes.licenceNumber ?? null,
      changes.licenceExpiry ?? null,
      changes.bankAccount ? JSON.stringify(changes.bankAccount) : null,
      changes.address ?? null,
      changes.emergencyContactName ?? null,
      changes.emergencyContactPhone ?? null,
    ],
  );
  return rows[0] || null;
}

async function setVerification(userId, { status, reason = null, adminId = null }, client = db) {
  const { rows } = await client.query(
    `UPDATE driver_profiles SET
       verification_status = $2::text,
       rejection_reason = $3,
       verified_at = CASE WHEN $2::text = 'APPROVED' THEN now() END,
       verified_by = CASE WHEN $2::text = 'APPROVED' THEN $4::uuid END,
       updated_at = now()
     WHERE user_id = $1
     RETURNING ${PROFILE_COLUMNS}`,
    [userId, status, reason, adminId],
  );
  return rows[0] || null;
}

async function setAccountStatus(userId, status, client = db) {
  const { rows } = await client.query(
    `UPDATE driver_profiles SET account_status = $2, updated_at = now()
     WHERE user_id = $1
     RETURNING ${PROFILE_COLUMNS}`,
    [userId, status],
  );
  return rows[0] || null;
}

/** Adds one rating to the running average in a single statement, so ratings cannot be lost. */
async function addRating(userId, stars, client = db) {
  const { rows } = await client.query(
    `UPDATE driver_profiles SET
       rating_avg = (rating_avg * rating_count + $2::int) / (rating_count + 1),
       rating_count = rating_count + 1,
       updated_at = now()
     WHERE user_id = $1
     RETURNING rating_avg::float8 AS rating_avg, rating_count`,
    [userId, stars],
  );
  return rows[0] || null;
}

async function listDocuments(userId, client = db) {
  const { rows } = await client.query(
    `SELECT id, driver_user_id, doc_type, storage_key, uploaded_at FROM driver_documents
     WHERE driver_user_id = $1 ORDER BY uploaded_at, id`,
    [userId],
  );
  return rows;
}

async function listDocumentsForDrivers(userIds, client = db) {
  if (userIds.length === 0) return [];
  const { rows } = await client.query(
    `SELECT id, driver_user_id, doc_type, storage_key, uploaded_at FROM driver_documents
     WHERE driver_user_id = ANY ($1::uuid[]) ORDER BY uploaded_at, id`,
    [userIds],
  );
  return rows;
}

async function findDocumentKey(userId, type, client = db) {
  const { rows } = await client.query(
    'SELECT storage_key FROM driver_documents WHERE driver_user_id = $1 AND doc_type = $2',
    [userId, type],
  );
  return rows[0]?.storage_key ?? null;
}

async function saveDocument(userId, type, storageKey, client = db) {
  const { rows } = await client.query(
    `INSERT INTO driver_documents (driver_user_id, doc_type, storage_key) VALUES ($1, $2, $3)
     ON CONFLICT (driver_user_id, doc_type)
     DO UPDATE SET storage_key = EXCLUDED.storage_key, uploaded_at = now()
     RETURNING id, driver_user_id, doc_type, storage_key, uploaded_at`,
    [userId, type, storageKey],
  );
  return rows[0];
}

async function findPublicProfile(userId, client = db) {
  const { rows } = await client.query(
    `SELECT d.user_id, d.verification_status, d.rating_avg::float8 AS rating_avg, d.rating_count,
            (u.created_at AT TIME ZONE 'UTC')::date::text AS member_since,
            u.full_name, u.avatar_url, photo.storage_key AS photo_key
     FROM driver_profiles d
     JOIN users u ON u.id = d.user_id
     LEFT JOIN driver_documents photo
       ON photo.driver_user_id = d.user_id AND photo.doc_type = 'PROFILE_PHOTO'
     WHERE d.user_id = $1`,
    [userId],
  );
  return rows[0] || null;
}

async function isEligible(userId, client = db) {
  const { rows } = await client.query(
    `SELECT 1 FROM driver_profiles
     WHERE user_id = $1 AND verification_status = 'APPROVED' AND account_status = 'ACTIVE'`,
    [userId],
  );
  return rows.length > 0;
}

/** The trips table belongs to the trip module, which may not be merged yet. */
async function tripsTableExists(client = db) {
  const { rows } = await client.query(
    "SELECT to_regclass('public.trips') IS NOT NULL AS present",
  );
  return rows[0].present;
}

async function countCompletedTrips(userId, { from = null, to = null } = {}, client = db) {
  if (!(await tripsTableExists(client))) return 0;
  const { rows } = await client.query(
    `SELECT count(*)::int AS total FROM trips
     WHERE driver_user_id = $1 AND status::text = 'COMPLETED'
       AND ($2::date IS NULL OR completed_at >= $2::date)
       AND ($3::date IS NULL OR completed_at < $3::date + 1)`,
    [userId, from, to],
  );
  return rows[0].total;
}

/** Returns one page of a driver's trips, newest first, and the total number of matches. */
async function listTrips(userId, { status = null, page, limit }, client = db) {
  if (!(await tripsTableExists(client))) return { trips: [], total: 0 };

  const filter = 'driver_user_id = $1 AND ($2::text IS NULL OR status::text = $2::text)';
  const count = await client.query(`SELECT count(*)::int AS total FROM trips WHERE ${filter}`, [
    userId,
    status,
  ]);
  const { rows } = await client.query(
    `SELECT id, vehicle_id, origin_name, destination_name, departure_at, estimated_arrival_at,
            pricing_mode, base_price_cents, seats_offered, seats_available, distance_m, duration_s,
            status, cancel_reason, started_at, completed_at, cancelled_at, created_at
     FROM trips WHERE ${filter}
     ORDER BY departure_at DESC, id
     LIMIT $3::int OFFSET $4::int`,
    [userId, status, limit, (page - 1) * limit],
  );
  return { trips: rows, total: count.rows[0].total };
}

async function writeAudit({ actorId, action, entityType, entityId, details }, client = db) {
  await client.query(
    `INSERT INTO audit_logs (actor_user_id, action, entity_type, entity_id, details)
     VALUES ($1, $2, $3, $4, $5::jsonb)`,
    [actorId, action, entityType, entityId, JSON.stringify(details ?? {})],
  );
}

module.exports = {
  findByUserId,
  lock,
  create,
  update,
  setVerification,
  setAccountStatus,
  addRating,
  listDocuments,
  listDocumentsForDrivers,
  findDocumentKey,
  saveDocument,
  findPublicProfile,
  isEligible,
  countCompletedTrips,
  listTrips,
  writeAudit,
};
