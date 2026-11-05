// Business rules for vehicles (SCRUM-48 to SCRUM-56). Routes stay thin and SQL stays in the
// repository, so every rule can be explained from this one file.
const db = require('../../db');
const storage = require('../../services/storage');
const ApiError = require('../../utils/ApiError');
const driverRepository = require('../drivers/driver.repository');
const { ROLES } = require('../users/user.constants');
const { REQUIRED_DOC_TYPES } = require('./vehicle.schemas');
const vehicleRepository = require('./vehicle.repository');
const { typeLimitErrors } = require('./vehicleTypes');

const MAX_VEHICLES_PER_DRIVER = 3;
const ENTITY_TYPE = 'VEHICLE';
const PG_UNIQUE_VIOLATION = '23505';
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Editing any of these on an APPROVED vehicle sends it back to PENDING (SCRUM-48).
const REVERIFY_FIELDS = [
  'plateNumber',
  'vehicleType',
  'totalSeats',
  'passengerSeats',
  'cargoCapacityKg',
  'cargoVolumeL',
];

const VEHICLE_FIELDS = {
  id: 'id',
  driverUserId: 'driver_user_id',
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
  verificationStatus: 'verification_status',
  rejectionReason: 'rejection_reason',
  verifiedAt: 'verified_at',
  verifiedBy: 'verified_by',
  isActive: 'is_active',
  createdAt: 'created_at',
  updatedAt: 'updated_at',
};

function toVehicle(row) {
  if (!row) return null;
  const vehicle = {};
  for (const [field, column] of Object.entries(VEHICLE_FIELDS)) vehicle[field] = row[column];
  return vehicle;
}

const toDocument = (row) => ({
  id: row.id,
  vehicleId: row.vehicle_id,
  docType: row.doc_type,
  fileUrl: storage.signedUrl(row.storage_key),
  status: row.status,
  uploadedAt: row.uploaded_at,
});

const notFound = () => new ApiError(404, 'VEHICLE_NOT_FOUND', 'Vehicle not found');
const plateTaken = () =>
  new ApiError(409, 'CONFLICT', 'A vehicle with this plate number is already registered');

const audit = (actorId, action, entityId, details, client) =>
  driverRepository.writeAudit({ actorId, action, entityType: ENTITY_TYPE, entityId, details }, client);

/** Other drivers get 404, so the API does not reveal which vehicle ids exist. */
function assertAccess(row, user, { allowAdmin = false } = {}) {
  if (!row) throw notFound();
  const isOwner = row.driver_user_id === user.id;
  if (!isOwner && !(allowAdmin && user.role === ROLES.ADMIN)) throw notFound();
  return row;
}

async function getAccessibleVehicle(user, id, options) {
  return assertAccess(await vehicleRepository.findById(id), user, options);
}

async function lockOwnedVehicle(user, id, tx) {
  return assertAccess(await vehicleRepository.lock(id, tx), user);
}

function assertTypeLimits(values) {
  const details = typeLimitErrors(values);
  if (details.length > 0) throw new ApiError(422, 'VALIDATION_ERROR', details[0].message, details);
}

async function assertNoOpenTrips(vehicleId, client) {
  if (await vehicleRepository.hasOpenTrips(vehicleId, client)) {
    throw new ApiError(
      409,
      'INVALID_STATE',
      'This vehicle has scheduled or in-progress trips. Complete or cancel them before deactivating.',
    );
  }
}

/** Required document types that are not uploaded yet, or were rejected by an admin. */
async function findMissingDocuments(vehicleId, client = db) {
  const documents = await vehicleRepository.listDocuments(vehicleId, client);
  const present = new Set(documents.filter((d) => d.status !== 'REJECTED').map((d) => d.doc_type));
  return REQUIRED_DOC_TYPES.filter((type) => !present.has(type));
}

async function loadDocuments(vehicleId) {
  return (await vehicleRepository.listDocuments(vehicleId)).map(toDocument);
}

// ---------------------------------------------------------------- driver side

// SCRUM-48, SCRUM-49, SCRUM-50, SCRUM-51, SCRUM-52
async function createVehicle(user, input) {
  const values = {
    ...input,
    passengerSeats: input.passengerSeats ?? input.totalSeats - 1,
    cargoCapacityKg: input.cargoCapacityKg ?? 0,
    cargoVolumeL: input.cargoVolumeL ?? 0,
  };
  assertTypeLimits(values);

  try {
    const row = await db.transaction(async (tx) => {
      await vehicleRepository.lockOwner(user.id, tx);
      if ((await vehicleRepository.countByDriver(user.id, tx)) >= MAX_VEHICLES_PER_DRIVER) {
        throw new ApiError(409, 'CONFLICT', `You can register at most ${MAX_VEHICLES_PER_DRIVER} vehicles`);
      }
      const created = await vehicleRepository.create(user.id, values, tx);
      await audit(user.id, 'VEHICLE_CREATED', created.id, { plateNumber: created.plate_number }, tx);
      return created;
    });
    return toVehicle(row);
  } catch (error) {
    if (error.code === PG_UNIQUE_VIOLATION) throw plateTaken();
    throw error;
  }
}

async function listMyVehicles(user) {
  return (await vehicleRepository.listByDriver(user.id)).map(toVehicle);
}

async function getVehicle(user, id) {
  return toVehicle(await getAccessibleVehicle(user, id, { allowAdmin: true }));
}

// SCRUM-48
async function updateVehicle(user, id, patch) {
  try {
    const row = await db.transaction(async (tx) => {
      const locked = await lockOwnedVehicle(user, id, tx);
      const current = toVehicle(locked);
      const changed = Object.keys(patch).filter(
        (field) => patch[field] !== undefined && patch[field] !== current[field],
      );
      if (changed.length === 0) return locked;

      // Limits apply to the final values, which mix the old ones with the new ones.
      assertTypeLimits({ ...current, ...patch });

      const changes = Object.fromEntries(changed.map((field) => [field, patch[field]]));
      let saved = await vehicleRepository.update(id, changes, tx);
      await audit(user.id, 'VEHICLE_UPDATED', id, { changedFields: changed }, tx);

      const reverifyFields = changed.filter((field) => REVERIFY_FIELDS.includes(field));
      if (locked.verification_status === 'APPROVED' && reverifyFields.length > 0) {
        saved = await vehicleRepository.setVerification(id, { status: 'PENDING' }, tx);
        await audit(
          user.id,
          'VEHICLE_REVERIFICATION_REQUIRED',
          id,
          { changedFields: reverifyFields, previousStatus: 'APPROVED' },
          tx,
        );
      }
      return saved;
    });
    return toVehicle(row);
  } catch (error) {
    if (error.code === PG_UNIQUE_VIOLATION) throw plateTaken();
    throw error;
  }
}

// SCRUM-53
async function listDocuments(user, id) {
  await getAccessibleVehicle(user, id, { allowAdmin: true });
  return loadDocuments(id);
}

// SCRUM-53
async function uploadDocument(user, id, docType, buffer) {
  await getAccessibleVehicle(user, id);

  const extension = storage.detectFileType(buffer);
  if (!extension) throw new ApiError(400, 'FILE_INVALID', 'File must be a JPG, PNG or PDF');

  const key = await storage.save(buffer, extension);
  let previousKey;
  let document;
  try {
    document = await db.transaction(async (tx) => {
      const row = await lockOwnedVehicle(user, id, tx);
      previousKey = await vehicleRepository.findDocumentKey(id, docType, tx);
      const saved = await vehicleRepository.saveDocument(id, docType, key, tx);

      // A new document on an APPROVED vehicle must be checked again by an admin.
      if (row.verification_status === 'APPROVED') {
        await vehicleRepository.setVerification(id, { status: 'PENDING' }, tx);
        await audit(
          user.id,
          'VEHICLE_REVERIFICATION_REQUIRED',
          id,
          { reason: `${docType} re-uploaded` },
          tx,
        );
      }
      await audit(user.id, 'VEHICLE_DOCUMENT_UPLOADED', id, { docType, documentId: saved.id }, tx);
      return saved;
    });
  } catch (error) {
    await storage.remove(key).catch(() => {});
    throw error;
  }
  if (previousKey) await storage.remove(previousKey).catch((error) => console.error(error));
  return toDocument(document);
}

// SCRUM-54
async function getVerification(user, id) {
  const row = await getAccessibleVehicle(user, id, { allowAdmin: true });
  return {
    vehicleId: row.id,
    status: row.verification_status,
    missingDocuments: await findMissingDocuments(id),
    rejectionReason: row.rejection_reason,
    verifiedAt: row.verified_at,
    documents: await loadDocuments(id),
  };
}

// SCRUM-54
async function submitVerification(user, id) {
  await db.transaction(async (tx) => {
    const row = await lockOwnedVehicle(user, id, tx);
    if (!['NOT_SUBMITTED', 'REJECTED'].includes(row.verification_status)) {
      throw new ApiError(
        409,
        'INVALID_STATE',
        `Vehicle is already ${row.verification_status}; it cannot be submitted again`,
      );
    }
    const missing = await findMissingDocuments(id, tx);
    if (missing.length > 0) {
      throw new ApiError(
        422,
        'VALIDATION_ERROR',
        'Upload all required documents before submitting',
        missing.map((docType) => ({ field: 'documents', docType, message: `${docType} is required` })),
      );
    }
    await vehicleRepository.setVerification(id, { status: 'PENDING' }, tx);
    await audit(user.id, 'VEHICLE_SUBMITTED', id, { previousStatus: row.verification_status }, tx);
  });
  return getVerification(user, id);
}

// SCRUM-56
async function setActive(user, id, isActive) {
  const row = await db.transaction(async (tx) => {
    const locked = await lockOwnedVehicle(user, id, tx);
    if (locked.is_active === isActive) return locked;

    if (!isActive) await assertNoOpenTrips(id, tx);
    // An admin's deactivation is final for the owner, until an admin reverses it.
    if (isActive) {
      const lastAction = await vehicleRepository.findLastAdminStatusAction(id, tx);
      if (lastAction === 'VEHICLE_ADMIN_DEACTIVATED') {
        throw new ApiError(
          403,
          'FORBIDDEN',
          'This vehicle was deactivated by an admin. Please contact support.',
        );
      }
    }
    const saved = await vehicleRepository.setActive(id, isActive, tx);
    await audit(user.id, isActive ? 'VEHICLE_ACTIVATED' : 'VEHICLE_DEACTIVATED', id, {}, tx);
    return saved;
  });
  return toVehicle(row);
}

// ---------------------------------------------------------------- admin side (SCRUM-55, SCRUM-56)

async function adminListVehicles(query) {
  const { vehicles, total } = await vehicleRepository.search(query);
  return {
    total,
    vehicles: vehicles.map((row) => ({
      ...toVehicle(row),
      owner: { id: row.driver_user_id, fullName: row.owner_full_name, phone: row.owner_phone },
    })),
  };
}

async function adminGetVehicle(id) {
  const row = await vehicleRepository.findWithOwner(id);
  if (!row) throw notFound();
  return {
    ...toVehicle(row),
    owner: {
      id: row.driver_user_id,
      fullName: row.owner_full_name,
      phone: row.owner_phone,
      driverVerificationStatus: row.driver_verification_status ?? null,
    },
    documents: await loadDocuments(id),
    missingDocuments: await findMissingDocuments(id),
  };
}

async function adminDecide(admin, id, { decision, reason, documents = [] }) {
  const approve = decision === 'APPROVE';

  await db.transaction(async (tx) => {
    const row = await vehicleRepository.lock(id, tx);
    if (!row) throw notFound();
    if (row.verification_status !== 'PENDING') {
      throw new ApiError(
        409,
        'INVALID_STATE',
        `Only PENDING vehicles can be reviewed (this one is ${row.verification_status})`,
      );
    }

    if (documents.length > 0) {
      const ids = [...new Set(documents.map((document) => document.id))];
      if ((await vehicleRepository.countDocuments(id, ids, tx)) !== ids.length) {
        throw new ApiError(422, 'VALIDATION_ERROR', 'documents[].id must belong to this vehicle');
      }
      for (const document of documents) {
        await vehicleRepository.setDocumentStatus(document.id, document.status, tx);
      }
    }

    if (approve) {
      const missing = await findMissingDocuments(id, tx);
      if (missing.length > 0) {
        throw new ApiError(
          422,
          'VALIDATION_ERROR',
          'Cannot approve: required documents are missing or rejected',
          missing.map((docType) => ({
            field: 'documents',
            docType,
            message: `${docType} is missing or rejected`,
          })),
        );
      }
      await vehicleRepository.acceptUploadedDocuments(id, tx);
    }

    await vehicleRepository.setVerification(
      id,
      {
        status: approve ? 'APPROVED' : 'REJECTED',
        reason: approve ? null : reason,
        adminId: admin.id,
      },
      tx,
    );
    await audit(
      admin.id,
      approve ? 'VEHICLE_APPROVED' : 'VEHICLE_REJECTED',
      id,
      { reason: reason ?? null, documents },
      tx,
    );
  });
  return adminGetVehicle(id);
}

async function adminSetStatus(admin, id, { isActive, reason }) {
  const row = await db.transaction(async (tx) => {
    const locked = await vehicleRepository.lock(id, tx);
    if (!locked) throw notFound();
    if (!isActive) await assertNoOpenTrips(id, tx);

    const saved = await vehicleRepository.setActive(id, isActive, tx);
    // Always logged: this record is also what stops the owner from re-activating.
    await audit(
      admin.id,
      isActive ? 'VEHICLE_ADMIN_ACTIVATED' : 'VEHICLE_ADMIN_DEACTIVATED',
      id,
      { reason: reason ?? null },
      tx,
    );
    return saved;
  });
  return toVehicle(row);
}

// ---------------------------------------------------------------- for the trip module

/** The vehicle if it belongs to the driver, is APPROVED and is active. Otherwise null. */
async function getUsableVehicle(vehicleId, driverUserId) {
  if (!UUID_PATTERN.test(String(vehicleId)) || !UUID_PATTERN.test(String(driverUserId))) return null;
  return toVehicle(await vehicleRepository.findUsable(vehicleId, driverUserId));
}

async function isVehicleUsable(vehicleId, driverUserId) {
  return Boolean(await getUsableVehicle(vehicleId, driverUserId));
}

module.exports = {
  MAX_VEHICLES_PER_DRIVER,
  createVehicle,
  listMyVehicles,
  getVehicle,
  updateVehicle,
  listDocuments,
  uploadDocument,
  getVerification,
  submitVerification,
  setActive,
  adminListVehicles,
  adminGetVehicle,
  adminDecide,
  adminSetStatus,
  getUsableVehicle,
  isVehicleUsable,
};
