// Checks that depend on other members' modules (drivers and vehicles).
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
 * Member 3 (vehicles): the vehicle must belong to the driver, be APPROVED and be active. This is
 * the same rule as vehicleRepository.findUsable / vehicleService.getUsableVehicle, checked here
 * column by column so the driver gets a specific error, and inside the caller's transaction.
 *
 * vehicles.passenger_seats is the number of seats the driver can sell. It already leaves out the
 * driver's own seat (the vehicles table enforces 1 <= passenger_seats < total_seats), so a trip
 * may offer up to passenger_seats seats.
 */
async function assertVehicleUsable(driverUserId, vehicleId, seatsOffered, client = db) {
  const { rows } = await client.query(
    `SELECT driver_user_id, verification_status, is_active, passenger_seats
     FROM vehicles WHERE id = $1`,
    [vehicleId],
  );
  const vehicle = rows[0];
  if (!vehicle || vehicle.driver_user_id !== driverUserId) {
    throw new ApiError(403, 'VEHICLE_NOT_OWNED', 'This vehicle is not registered to you');
  }
  if (vehicle.verification_status !== 'APPROVED') {
    throw new ApiError(403, 'VEHICLE_NOT_APPROVED', 'This vehicle is not approved yet');
  }
  if (!vehicle.is_active) {
    throw new ApiError(403, 'VEHICLE_INACTIVE', 'This vehicle is deactivated. Activate it before offering trips');
  }
  if (seatsOffered > vehicle.passenger_seats) {
    throw new ApiError(
      422,
      'TOO_MANY_SEATS',
      `This vehicle can offer at most ${vehicle.passenger_seats} seats`,
    );
  }
}

/** Notifications (sprint 4) will tell passengers with seats. No-op for now. */
async function onTripCancelled() {}

module.exports = { assertDriverEligible, assertVehicleUsable, onTripCancelled };
