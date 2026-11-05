// SCRUM-49 / SCRUM-50 / SCRUM-52
// Per-type limits. Validation (create + edit) and the app dropdown both read this file,
// so changing a limit here changes it everywhere.
//
// minSeats / maxSeats  -> totalSeats INCLUDING the driver
// maxCargoKg           -> cargoCapacityKg upper limit (0 would mean "no cargo allowed")
// maxCargoVolumeL      -> cargoVolumeL upper limit

const VEHICLE_TYPES = Object.freeze({
  CAR: { label: 'Car', minSeats: 2, maxSeats: 5, maxCargoKg: 100, maxCargoVolumeL: 500 },
  SUV: { label: 'SUV', minSeats: 5, maxSeats: 8, maxCargoKg: 200, maxCargoVolumeL: 800 },
  VAN: { label: 'Van', minSeats: 5, maxSeats: 15, maxCargoKg: 800, maxCargoVolumeL: 3000 },
  MINIBUS: { label: 'Mini bus', minSeats: 10, maxSeats: 30, maxCargoKg: 500, maxCargoVolumeL: 2000 },
  BUS: { label: 'Bus', minSeats: 20, maxSeats: 60, maxCargoKg: 1000, maxCargoVolumeL: 5000 },
  PICKUP: { label: 'Pickup / Cab', minSeats: 2, maxSeats: 5, maxCargoKg: 1000, maxCargoVolumeL: 3000 },
  LORRY: { label: 'Lorry', minSeats: 2, maxSeats: 3, maxCargoKg: 5000, maxCargoVolumeL: 20000 },
});

const VEHICLE_TYPE_KEYS = Object.keys(VEHICLE_TYPES);

// Shape returned by GET /api/v1/vehicles/types
function listVehicleTypes() {
  return VEHICLE_TYPE_KEYS.map((type) => ({
    type,
    ...VEHICLE_TYPES[type],
    allowsCargo: VEHICLE_TYPES[type].maxCargoKg > 0,
  }));
}

/**
 * Checks seats + cargo against the type limits.
 * @param {{vehicleType, totalSeats, passengerSeats, cargoCapacityKg, cargoVolumeL}} v
 * @returns {Array<{field: string, message: string}>} empty array = valid
 */
function typeLimitErrors(v) {
  const errors = [];
  const limits = VEHICLE_TYPES[v.vehicleType];
  if (!limits) {
    errors.push({ field: 'vehicleType', message: `vehicleType must be one of ${VEHICLE_TYPE_KEYS.join(', ')}` });
    return errors;
  }

  if (v.totalSeats < limits.minSeats || v.totalSeats > limits.maxSeats) {
    errors.push({
      field: 'totalSeats',
      message: `A ${v.vehicleType} must have ${limits.minSeats}-${limits.maxSeats} seats (including the driver)`,
    });
  }

  // SCRUM-51: seats the driver can sell. At least 1, and the driver keeps one seat.
  if (v.passengerSeats < 1 || v.passengerSeats >= v.totalSeats) {
    errors.push({
      field: 'passengerSeats',
      message: 'passengerSeats must be at least 1 and less than totalSeats',
    });
  }

  if (v.cargoCapacityKg < 0 || v.cargoCapacityKg > limits.maxCargoKg) {
    errors.push({ field: 'cargoCapacityKg', message: `A ${v.vehicleType} can carry 0-${limits.maxCargoKg} kg` });
  }
  if (v.cargoVolumeL < 0 || v.cargoVolumeL > limits.maxCargoVolumeL) {
    errors.push({ field: 'cargoVolumeL', message: `A ${v.vehicleType} can carry 0-${limits.maxCargoVolumeL} L` });
  }
  return errors;
}

module.exports = { VEHICLE_TYPES, VEHICLE_TYPE_KEYS, listVehicleTypes, typeLimitErrors };
