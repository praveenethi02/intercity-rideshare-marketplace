// Checks that depend on other members' modules. Each one looks for the other module's table
// first, so the trips module works before and after those modules are merged.
const db = require('../../db');
const ApiError = require('../../utils/ApiError');

async function tableExists(table, client = db) {
  const { rows } = await client.query('SELECT to_regclass($1) IS NOT NULL AS present', [
    `public.${table}`,
  ]);
  return rows[0].present;
}

/**
 * Member 2 (driver verification): the driver profile must be APPROVED and ACTIVE.
 * Same rule as driverRepository.isEligible in the drivers module.
 */
async function assertDriverEligible(userId, client = db) {
  if (!(await tableExists('driver_profiles', client))) return;
  const { rows } = await client.query(
    `SELECT 1 FROM driver_profiles
     WHERE user_id = $1 AND verification_status = 'APPROVED' AND account_status = 'ACTIVE'`,
    [userId],
  );
  if (rows.length === 0) {
    throw new ApiError(403, 'DRIVER_NOT_VERIFIED', 'Your driver profile must be approved before you offer trips');
  }
}

/**
 * Member 3 (vehicles): the vehicle must belong to the driver and be APPROVED, and the driver's
 * own seat is not for sale. ASSUMED columns: vehicles(id, owner_user_id, status, seat_capacity).
 * Rename them here to match the vehicles migration when it is merged.
 */
async function assertVehicleUsable(driverUserId, vehicleId, seatsOffered, client = db) {
  if (!(await tableExists('vehicles', client))) return;
  const { rows } = await client.query(
    'SELECT owner_user_id, status, seat_capacity FROM vehicles WHERE id = $1',
    [vehicleId],
  );
  const vehicle = rows[0];
  if (!vehicle || vehicle.owner_user_id !== driverUserId) {
    throw new ApiError(403, 'VEHICLE_NOT_OWNED', 'This vehicle is not registered to you');
  }
  if (vehicle.status !== 'APPROVED') {
    throw new ApiError(403, 'VEHICLE_NOT_APPROVED', 'This vehicle is not approved yet');
  }
  if (seatsOffered > vehicle.seat_capacity - 1) {
    throw new ApiError(422, 'TOO_MANY_SEATS', `This vehicle can offer at most ${vehicle.seat_capacity - 1} seats`);
  }
}

/** Notifications (sprint 4) will tell passengers with seats. No-op for now. */
async function onTripCancelled() {}

module.exports = { assertDriverEligible, assertVehicleUsable, onTripCancelled };
