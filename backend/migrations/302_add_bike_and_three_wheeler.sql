-- Drivers can register motorbikes and three-wheelers.
-- Keep this list the same as VEHICLE_TYPES in src/modules/vehicles/vehicleTypes.js.

ALTER TABLE vehicles DROP CONSTRAINT vehicles_vehicle_type_check;

ALTER TABLE vehicles ADD CONSTRAINT vehicles_vehicle_type_check
  CHECK (vehicle_type IN ('CAR', 'THREE_WHEELER', 'MOTORBIKE', 'VAN', 'SUV', 'MINIBUS', 'BUS', 'PICKUP', 'LORRY'));
