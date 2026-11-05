const { haversineKm, withDistanceFromStart, boundingBox } = require('../src/modules/trips/geo');
const { legsFor, availableSeats, segmentPriceCents } = require('../src/modules/trips/segments');
const { canTransition, editableFields } = require('../src/modules/trips/trip-lifecycle');

const colombo = { lat: 6.9271, lng: 79.8612 };
const kandy = { lat: 7.2906, lng: 80.6337 };

describe('geo', () => {
  test('Colombo to Kandy is about 94 km in a straight line', () => {
    expect(haversineKm(colombo, kandy)).toBeGreaterThan(90);
    expect(haversineKm(colombo, kandy)).toBeLessThan(98);
  });

  test('distance from start begins at 0 and grows', () => {
    const stops = withDistanceFromStart([colombo, { lat: 7.0873, lng: 80.0144 }, kandy]);
    expect(stops[0].distance_from_start_m).toBe(0);
    expect(stops[1].distance_from_start_m).toBeGreaterThan(0);
    expect(stops[2].distance_from_start_m).toBeGreaterThan(stops[1].distance_from_start_m);
  });

  test('bounding box contains its centre', () => {
    const box = boundingBox(colombo, 5);
    expect(box.minLat).toBeLessThan(colombo.lat);
    expect(box.maxLat).toBeGreaterThan(colombo.lat);
    expect(box.minLng).toBeLessThan(colombo.lng);
    expect(box.maxLng).toBeGreaterThan(colombo.lng);
  });
});

describe('seats per route segment', () => {
  test('legsFor lists the legs between pickup and drop', () => {
    expect(legsFor(0, 3)).toEqual([0, 1, 2]);
    expect(legsFor(1, 2)).toEqual([1]);
  });

  test.each([
    [2, 2],
    [3, 1],
    [-1, 1],
  ])('legsFor rejects pickup %i and drop %i', (from, to) => {
    expect(() => legsFor(from, to)).toThrow(RangeError);
  });

  test('segments that do not overlap can share a seat', () => {
    const reserved = [4, 4, 0]; // A->C is full, C->D is free
    expect(availableSeats(4, reserved, 0, 3)).toBe(0);
    expect(availableSeats(4, reserved, 2, 3)).toBe(4);
  });

  test('the busiest leg decides', () => {
    expect(availableSeats(4, [1, 3, 2], 0, 3)).toBe(1);
    expect(availableSeats(4, [1, 3, 2], 0, 1)).toBe(3);
  });

  test('segment price follows distance and rounds to LKR 10', () => {
    expect(segmentPriceCents(200000, 100000, 0, 25000)).toBe(50000);
    expect(segmentPriceCents(200000, 100000, 0, 100000)).toBe(200000);
    expect(segmentPriceCents(123456, 100000, 0, 33000) % 1000).toBe(0);
  });
});

describe('trip lifecycle', () => {
  test.each([
    ['DRAFT', 'SCHEDULED'],
    ['SCHEDULED', 'IN_PROGRESS'],
    ['IN_PROGRESS', 'COMPLETED'],
    ['DRAFT', 'CANCELLED'],
    ['SCHEDULED', 'CANCELLED'],
  ])('%s can become %s', (from, to) => expect(canTransition(from, to)).toBe(true));

  test.each([
    ['DRAFT', 'COMPLETED'],
    ['IN_PROGRESS', 'CANCELLED'],
    ['COMPLETED', 'SCHEDULED'],
    ['CANCELLED', 'SCHEDULED'],
  ])('%s cannot become %s', (from, to) => expect(canTransition(from, to)).toBe(false));

  test('fewer fields are editable once seats are reserved', () => {
    expect(editableFields('DRAFT', false)).toBe('ALL');
    expect(editableFields('SCHEDULED', false)).toContain('seatsOffered');
    expect(editableFields('SCHEDULED', true)).not.toContain('seatsOffered');
    expect(editableFields('COMPLETED', false)).toEqual([]);
  });
});
