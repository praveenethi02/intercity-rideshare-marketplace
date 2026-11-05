// Unit tests: no DB needed.
const { normalizePlate, isValidPlate } = require('../../src/modules/vehicles/plate');
const { typeLimitErrors } = require('../../src/modules/vehicles/vehicleTypes');

describe('normalizePlate (SCRUM-49)', () => {
  test.each([
    ['wp cab-1234', 'WP CAB-1234'],
    ['WP  CAB 1234', 'WP CAB-1234'],
    ['  wp cab - 1234 ', 'WP CAB-1234'],
    ['cab1234', 'CAB-1234'],
    ['CAB – 1234', 'CAB-1234'], // en-dash
    ['kx-1234', 'KX-1234'],
    ['65 1234', '65-1234'],
    ['2501234', '250-1234'],
    ['sg ka 1234', 'SG KA-1234'],
  ])('%p -> %p', (input, expected) => {
    expect(normalizePlate(input)).toBe(expected);
    expect(isValidPlate(normalizePlate(input))).toBe(true);
  });

  test.each(['XX CAB-1234', 'CABC-1234', 'AB-12', '1-1234', '', 'WP-CAB-1234-9'])('rejects %p', (input) => {
    expect(isValidPlate(normalizePlate(input))).toBe(false);
  });
});

describe('typeLimitErrors (SCRUM-50/51/52)', () => {
  const car = { vehicleType: 'CAR', totalSeats: 5, passengerSeats: 4, cargoCapacityKg: 50, cargoVolumeL: 300 };

  test('valid car has no errors', () => {
    expect(typeLimitErrors(car)).toEqual([]);
  });
  test('car with 7 seats is outside limits', () => {
    expect(typeLimitErrors({ ...car, totalSeats: 7, passengerSeats: 6 }).map((e) => e.field)).toEqual(['totalSeats']);
  });
  test('passengerSeats must be < totalSeats and >= 1', () => {
    expect(typeLimitErrors({ ...car, passengerSeats: 5 }).map((e) => e.field)).toEqual(['passengerSeats']);
    expect(typeLimitErrors({ ...car, passengerSeats: 0 }).map((e) => e.field)).toEqual(['passengerSeats']);
  });
  test('cargo above the type limit', () => {
    expect(typeLimitErrors({ ...car, cargoCapacityKg: 101 }).map((e) => e.field)).toEqual(['cargoCapacityKg']);
  });
  test('lorry may carry 5000 kg', () => {
    expect(
      typeLimitErrors({ vehicleType: 'LORRY', totalSeats: 3, passengerSeats: 2, cargoCapacityKg: 5000, cargoVolumeL: 0 })
    ).toEqual([]);
  });
});
