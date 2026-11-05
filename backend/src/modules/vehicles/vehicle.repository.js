const db = require('../../db');

// camelCase API field -> snake_case column. Only these names ever reach the SQL text.
const COLUMNS = {
  vehicleType: 'vehicle_type',
  make: 'make',
  model: 'model',
  year: 'year',
  color: 'color',
  plateNumber: 'plate_number',
  totalSeats: 'total_seats',
  passengerSeats: 'passenger_seats',
  cargoCapacityKg: 'cargo_capacity_kg',
  cargoVolumeL: 'cargo_volume_l',
};

async function findById(id, client = db) {
  const { rows } = await client.query('SELECT * FROM vehicles WHERE id = $1', [id]);
  return rows[0] || null;
}

/** Locks the vehicle until the transaction ends, so concurrent changes run one at a time. */
async function lock(id, client) {
  const { rows } = await client.query('SELECT * FROM vehicles WHERE id = $1 FOR UPDATE', [id]);
  return rows[0] || null;
}

/** Locks the owner, so two requests at once cannot both pass the vehicle limit. */
async function lockOwner(userId, client) {
  await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [userId]);
}

async function countByDriver(userId, client = db) {
  const { rows } = await client.query(
    'SELECT count(*)::int AS total FROM vehicles WHERE driver_user_id = $1',
    [userId],
  );
  return rows[0].total;
}

async function create(userId, values, client = db) {
  const fields = Object.keys(COLUMNS);
  const columns = fields.map((field) => COLUMNS[field]).join(', ');
  const placeholders = fields.map((_, i) => `$${i + 2}`).join(', ');
  const { rows } = await client.query(
    `INSERT INTO vehicles (driver_user_id, ${columns}) VALUES ($1, ${placeholders}) RETURNING *`,
    [userId, ...fields.map((field) => values[field])],
  );
  return rows[0];
}

async function listByDriver(userId, client = db) {
  const { rows } = await client.query(
    'SELECT * FROM vehicles WHERE driver_user_id = $1 ORDER BY created_at, id',
    [userId],
  );
  return rows;
}

async function update(id, changes, client = db) {
  const fields = Object.keys(changes);
  const assignments = fields.map((field, i) => `${COLUMNS[field]} = $${i + 2}`).join(', ');
  const { rows } = await client.query(
    `UPDATE vehicles SET ${assignments}, updated_at = now() WHERE id = $1 RETURNING *`,
    [id, ...fields.map((field) => changes[field])],
  );
  return rows[0];
}

async function setVerification(id, { status, reason = null, adminId = null }, client = db) {
  const { rows } = await client.query(
    `UPDATE vehicles SET
       verification_status = $2::text,
       rejection_reason = $3,
       verified_at = CASE WHEN $2::text = 'APPROVED' THEN now() END,
       verified_by = $4::uuid,
       updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [id, status, reason, adminId],
  );
  return rows[0];
}

async function setActive(id, isActive, client = db) {
  const { rows } = await client.query(
    'UPDATE vehicles SET is_active = $2, updated_at = now() WHERE id = $1 RETURNING *',
    [id, isActive],
  );
  return rows[0];
}

async function listDocuments(vehicleId, client = db) {
  const { rows } = await client.query(
    'SELECT * FROM vehicle_documents WHERE vehicle_id = $1 ORDER BY doc_type',
    [vehicleId],
  );
  return rows;
}

async function findDocumentKey(vehicleId, docType, client = db) {
  const { rows } = await client.query(
    'SELECT storage_key FROM vehicle_documents WHERE vehicle_id = $1 AND doc_type = $2',
    [vehicleId, docType],
  );
  return rows[0]?.storage_key ?? null;
}

async function saveDocument(vehicleId, docType, storageKey, client = db) {
  const { rows } = await client.query(
    `INSERT INTO vehicle_documents (vehicle_id, doc_type, storage_key) VALUES ($1, $2, $3)
     ON CONFLICT (vehicle_id, doc_type)
     DO UPDATE SET storage_key = EXCLUDED.storage_key, status = 'UPLOADED', uploaded_at = now()
     RETURNING *`,
    [vehicleId, docType, storageKey],
  );
  return rows[0];
}

/** How many of these document ids belong to the vehicle. */
async function countDocuments(vehicleId, ids, client = db) {
  const { rows } = await client.query(
    `SELECT count(*)::int AS total FROM vehicle_documents
     WHERE vehicle_id = $1 AND id = ANY ($2::uuid[])`,
    [vehicleId, ids],
  );
  return rows[0].total;
}

async function setDocumentStatus(id, status, client = db) {
  await client.query('UPDATE vehicle_documents SET status = $2 WHERE id = $1', [id, status]);
}

async function acceptUploadedDocuments(vehicleId, client = db) {
  await client.query(
    `UPDATE vehicle_documents SET status = 'ACCEPTED'
     WHERE vehicle_id = $1 AND status = 'UPLOADED'`,
    [vehicleId],
  );
}

/** The trips table belongs to the trip module, which may not be merged yet. */
async function hasOpenTrips(vehicleId, client = db) {
  const { rows: table } = await client.query(
    "SELECT to_regclass('public.trips') IS NOT NULL AS present",
  );
  if (!table[0].present) return false;

  const { rows } = await client.query(
    `SELECT 1 FROM trips
     WHERE vehicle_id = $1 AND status::text IN ('SCHEDULED', 'IN_PROGRESS')
     LIMIT 1`,
    [vehicleId],
  );
  return rows.length > 0;
}

/** The latest admin activate or deactivate action recorded for a vehicle, if any. */
async function findLastAdminStatusAction(vehicleId, client = db) {
  const { rows } = await client.query(
    `SELECT action FROM audit_logs
     WHERE entity_type = 'VEHICLE' AND entity_id = $1
       AND action IN ('VEHICLE_ADMIN_DEACTIVATED', 'VEHICLE_ADMIN_ACTIVATED')
     ORDER BY created_at DESC
     LIMIT 1`,
    [vehicleId],
  );
  return rows[0]?.action ?? null;
}

const WITH_OWNER = `SELECT v.*, u.full_name AS owner_full_name, u.phone AS owner_phone
  FROM vehicles v JOIN users u ON u.id = v.driver_user_id`;

/** Returns one page of vehicles with their owners, and the total number of matches. */
async function search({ verificationStatus, type, isActive, q, page, limit }, client = db) {
  const like = q ? `%${q.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : null;
  const filter = `WHERE ($1::text IS NULL OR v.verification_status = $1::text)
    AND ($2::text IS NULL OR v.vehicle_type = $2::text)
    AND ($3::boolean IS NULL OR v.is_active = $3::boolean)
    AND ($4::text IS NULL OR v.plate_number ILIKE $4::text OR v.make ILIKE $4::text
         OR v.model ILIKE $4::text OR u.full_name ILIKE $4::text OR u.phone ILIKE $4::text)`;
  const params = [
    verificationStatus ?? null,
    type ?? null,
    isActive === undefined ? null : isActive === 'true',
    like,
  ];

  const count = await client.query(
    `SELECT count(*)::int AS total FROM vehicles v JOIN users u ON u.id = v.driver_user_id ${filter}`,
    params,
  );
  // The pending queue shows whoever has waited longest first. Other lists show the newest first.
  const direction = verificationStatus === 'PENDING' ? 'ASC' : 'DESC';
  const { rows } = await client.query(
    `${WITH_OWNER} ${filter}
     ORDER BY v.updated_at ${direction}, v.id
     LIMIT $5::int OFFSET $6::int`,
    [...params, limit, (page - 1) * limit],
  );
  return { vehicles: rows, total: count.rows[0].total };
}

async function findWithOwner(id, client = db) {
  const { rows } = await client.query(
    `SELECT v.*, u.full_name AS owner_full_name, u.phone AS owner_phone,
            d.verification_status AS driver_verification_status
     FROM vehicles v
     JOIN users u ON u.id = v.driver_user_id
     LEFT JOIN driver_profiles d ON d.user_id = v.driver_user_id
     WHERE v.id = $1`,
    [id],
  );
  return rows[0] || null;
}

async function findUsable(vehicleId, driverUserId, client = db) {
  const { rows } = await client.query(
    `SELECT * FROM vehicles
     WHERE id = $1 AND driver_user_id = $2 AND verification_status = 'APPROVED' AND is_active`,
    [vehicleId, driverUserId],
  );
  return rows[0] || null;
}

module.exports = {
  findById,
  lock,
  lockOwner,
  countByDriver,
  create,
  listByDriver,
  update,
  setVerification,
  setActive,
  listDocuments,
  findDocumentKey,
  saveDocument,
  countDocuments,
  setDocumentStatus,
  acceptUploadedDocuments,
  hasOpenTrips,
  findLastAdminStatusAction,
  search,
  findWithOwner,
  findUsable,
};
