const db = require('../../db');
const storage = require('../../services/storage');
const ApiError = require('../../utils/ApiError');
const userRepository = require('../users/user.repository');
const { ROLES } = require('../users/user.constants');
const { DOCUMENT_TYPES, VERIFICATION_STATUS } = require('./driver.constants');
const driverRepository = require('./driver.repository');
const verificationRepository = require('./verification.repository');

const PG_UNIQUE_VIOLATION = '23505';
const PROFILE_PHOTO = 'PROFILE_PHOTO';

function toConflict(error) {
  if (error.code !== PG_UNIQUE_VIOLATION) return error;
  return error.constraint === 'driver_profiles_pkey'
    ? new ApiError(409, 'DRIVER_EXISTS', 'You are already registered as a driver')
    : new ApiError(409, 'IDENTITY_IN_USE', 'This licence or NIC is already registered to another driver');
}

/** "Nimal Silva" becomes "Nimal S." so public profiles do not expose full names. */
function shortName(fullName) {
  const [first, ...rest] = fullName.trim().split(/\s+/);
  return rest.length ? `${first} ${rest.at(-1)[0].toUpperCase()}.` : first;
}

const toDocument = (row) => ({
  id: row.id,
  type: row.doc_type,
  url: storage.signedUrl(row.storage_key),
  uploadedAt: row.uploaded_at,
});

async function toProfile(driver) {
  const [documents, completedTrips] = await Promise.all([
    driverRepository.listDocuments(driver.user_id),
    driverRepository.countCompletedTrips(driver.user_id),
  ]);
  return {
    id: driver.user_id,
    userId: driver.user_id,
    licenceNumber: driver.license_number,
    licenceExpiry: driver.license_expiry,
    dateOfBirth: driver.date_of_birth,
    address: driver.address,
    emergencyContactName: driver.emergency_contact_name,
    emergencyContactPhone: driver.emergency_contact_phone,
    verification: driver.verification_status,
    rejectionReason: driver.rejection_reason,
    verifiedAt: driver.verified_at,
    accountStatus: driver.account_status,
    averageRating: driver.rating_avg,
    ratingCount: driver.rating_count,
    completedTrips,
    documents: documents.map(toDocument),
  };
}

/**
 * Puts a driver back in review after their details change, and opens a queue entry once every
 * document is present.
 */
async function reopenVerification(userId, tx) {
  const driver = await driverRepository.setVerification(
    userId,
    { status: VERIFICATION_STATUS.PENDING },
    tx,
  );
  const documents = await driverRepository.listDocuments(userId, tx);
  const present = new Set(documents.map((document) => document.doc_type));
  if (DOCUMENT_TYPES.every((type) => present.has(type))) {
    await verificationRepository.openForDriver(userId, tx);
  }
  return driver;
}

// SCRUM-38
async function register(user, details) {
  if (user.role === ROLES.ADMIN) {
    throw new ApiError(403, 'ADMIN_ROLE_LOCKED', 'Admin accounts cannot become drivers');
  }
  try {
    const driver = await db.transaction(async (tx) => {
      const created = await driverRepository.create(user.id, details, tx);
      await userRepository.updateRole(user.id, ROLES.DRIVER, tx);
      return created;
    });
    return await toProfile(driver);
  } catch (error) {
    throw toConflict(error);
  }
}

// SCRUM-39
async function update(driver, changes) {
  try {
    const updated = await db.transaction(async (tx) => {
      const current = await driverRepository.lock(driver.user_id, tx);
      const licenceChanged =
        (changes.licenceNumber !== undefined && changes.licenceNumber !== current.license_number) ||
        (changes.licenceExpiry !== undefined && changes.licenceExpiry !== current.license_expiry);

      const saved = await driverRepository.update(driver.user_id, changes, tx);
      if (!licenceChanged) return saved;

      if (current.verification_status === VERIFICATION_STATUS.APPROVED) {
        await driverRepository.writeAudit(
          {
            actorId: driver.user_id,
            action: 'DRIVER_LICENCE_CHANGED_AFTER_APPROVAL',
            entityType: 'DRIVER',
            entityId: driver.user_id,
          },
          tx,
        );
      }
      return reopenVerification(driver.user_id, tx);
    });
    return await toProfile(updated);
  } catch (error) {
    throw toConflict(error);
  }
}

// SCRUM-40, SCRUM-41
async function addDocument(driver, type, buffer) {
  const extension = storage.detectFileType(buffer);
  if (!extension) throw new ApiError(400, 'FILE_INVALID', 'File must be a JPG, PNG or PDF');

  const key = await storage.save(buffer, extension);
  let previousKey;
  let document;
  try {
    document = await db.transaction(async (tx) => {
      // Locking the profile stops two uploads opening a review at the same moment.
      const current = await driverRepository.lock(driver.user_id, tx);
      previousKey = await driverRepository.findDocumentKey(driver.user_id, type, tx);
      const saved = await driverRepository.saveDocument(driver.user_id, type, key, tx);

      // A new photo proves nothing about identity, so an approved driver stays approved.
      const stayApproved =
        type === PROFILE_PHOTO && current.verification_status === VERIFICATION_STATUS.APPROVED;
      if (!stayApproved) await reopenVerification(driver.user_id, tx);
      return saved;
    });
  } catch (error) {
    await storage.remove(key).catch(() => {});
    throw error;
  }
  if (previousKey) await storage.remove(previousKey).catch((error) => console.error(error));
  return toDocument(document);
}

// SCRUM-42
async function getVerification(driver) {
  const [request, documents] = await Promise.all([
    verificationRepository.findLatestForDriver(driver.user_id),
    driverRepository.listDocuments(driver.user_id),
  ]);
  const present = new Set(documents.map((document) => document.doc_type));
  return {
    // id and submittedAt stay null until every document is uploaded.
    id: request?.id ?? null,
    type: 'DRIVER',
    subjectId: driver.user_id,
    status: driver.verification_status,
    reason: driver.rejection_reason,
    missingDocuments: DOCUMENT_TYPES.filter((type) => !present.has(type)),
    documents: documents.map(toDocument),
    submittedAt: request?.submitted_at ?? null,
    decidedAt: request?.decided_at ?? null,
    decidedBy: request?.decided_by ?? null,
  };
}

async function getPublicProfile(userId) {
  const row = await driverRepository.findPublicProfile(userId);
  if (!row) throw new ApiError(404, 'DRIVER_NOT_FOUND', 'Driver not found');
  return {
    id: row.user_id,
    fullName: shortName(row.full_name),
    photoUrl: row.photo_key ? storage.signedUrl(row.photo_key) : row.avatar_url,
    averageRating: row.rating_avg,
    ratingCount: row.rating_count,
    completedTrips: await driverRepository.countCompletedTrips(row.user_id),
    verifiedDriver: row.verification_status === VERIFICATION_STATUS.APPROVED,
    memberSince: row.member_since,
  };
}

// SCRUM-44
async function listTrips(driver, query) {
  const { trips, total } = await driverRepository.listTrips(driver.user_id, query);
  return {
    total,
    trips: trips.map((trip) => ({
      id: trip.id,
      vehicleId: trip.vehicle_id,
      originName: trip.origin_name,
      destinationName: trip.destination_name,
      departureAt: trip.departure_at,
      estimatedArrivalAt: trip.estimated_arrival_at,
      pricingMode: trip.pricing_mode,
      basePriceCents: trip.base_price_cents,
      seatsOffered: trip.seats_offered,
      seatsAvailable: trip.seats_available,
      distanceM: trip.distance_m,
      durationS: trip.duration_s,
      status: trip.status,
      cancelReason: trip.cancel_reason,
      startedAt: trip.started_at,
      completedAt: trip.completed_at,
      cancelledAt: trip.cancelled_at,
      createdAt: trip.created_at,
    })),
  };
}

// SCRUM-45: the amounts stay at zero until settled payments exist (payments module, Sprint 6).
async function getEarnings(driver, { from, to }) {
  return {
    currency: 'LKR',
    seatEarnings: 0,
    cargoEarnings: 0,
    platformFees: 0,
    paidOut: 0,
    pendingPayout: 0,
    completedTrips: await driverRepository.countCompletedTrips(driver.user_id, { from, to }),
    periodFrom: from ?? null,
    periodTo: to ?? null,
  };
}

// SCRUM-46: called by the ratings module once it exists (Sprint 4), so it has no endpoint yet.
async function applyRating(driverUserId, stars) {
  if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
    throw new ApiError(422, 'VALIDATION_ERROR', 'Stars must be a whole number from 1 to 5');
  }
  const result = await driverRepository.addRating(driverUserId, stars);
  if (!result) throw new ApiError(404, 'DRIVER_NOT_FOUND', 'Driver not found');
  return { averageRating: result.rating_avg, ratingCount: result.rating_count };
}

/** True only for an approved, active driver: the rule for publishing trips (SCRUM-47). */
const isDriverEligible = (userId) => driverRepository.isEligible(userId);

module.exports = {
  toProfile,
  toDocument,
  register,
  update,
  addDocument,
  getVerification,
  getPublicProfile,
  listTrips,
  getEarnings,
  applyRating,
  isDriverEligible,
};
