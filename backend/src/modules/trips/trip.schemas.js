const { z } = require('zod');
const { TRIP_STATUS, PRICING_MODE, TRIP_RULES, SEARCH_SORT } = require('./trip.constants');

const dateTime = z.iso.datetime({ offset: true });
const priceCents = z.number().int().min(0).max(10_000_000); // up to LKR 100,000
const seats = z.number().int().min(1).max(TRIP_RULES.MAX_SEATS);
const cargoKg = z.number().positive().max(2000);

const stop = z.strictObject({
  name: z.string().trim().min(2).max(120),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  plannedAt: dateTime.optional(),
});

const stops = z.array(stop).min(TRIP_RULES.MIN_STOPS, 'Add at least a start and an end point').max(TRIP_RULES.MAX_STOPS);

const createTrip = z
  .strictObject({
    vehicleId: z.uuid(),
    pricingMode: z.enum(Object.values(PRICING_MODE)),
    departureAt: dateTime,
    estimatedArrivalAt: dateTime.optional(),
    seatsOffered: seats,
    basePriceCents: priceCents,
    allowsCargo: z.boolean().default(false),
    cargoCapacityKg: cargoKg.optional(),
    notes: z.string().trim().max(500).optional(),
    stops,
  })
  .refine((trip) => !trip.allowsCargo || trip.cargoCapacityKg, {
    message: 'cargoCapacityKg is required when allowsCargo is true',
    path: ['cargoCapacityKg'],
  });

const updateTrip = z
  .strictObject({
    departureAt: dateTime.optional(),
    estimatedArrivalAt: dateTime.optional(),
    seatsOffered: seats.optional(),
    basePriceCents: priceCents.optional(),
    allowsCargo: z.boolean().optional(),
    cargoCapacityKg: cargoKg.optional(),
    notes: z.string().trim().max(500).optional(),
    stops: stops.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, { message: 'Provide at least one field' });

const tripIdParams = z.strictObject({ id: z.uuid() });

const cancelTrip = z.strictObject({ reason: z.string().trim().min(3).max(300) });

const latitude = z.coerce.number().min(-90).max(90);
const longitude = z.coerce.number().min(-180).max(180);

/** A Sri Lankan clock time, "HH:mm" (00:00 to 23:59). */
const clockTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Use the 24-hour format HH:mm');

const searchQuery = z
  .strictObject({
    fromLat: latitude,
    fromLng: longitude,
    toLat: latitude,
    toLng: longitude,
    date: z.iso.date(),
    seats: z.coerce.number().int().min(1).max(TRIP_RULES.MAX_SEATS).default(1),
    radiusKm: z.coerce.number().min(0.5).max(30).default(TRIP_RULES.DEFAULT_SEARCH_RADIUS_KM),
    pricingMode: z.enum(Object.values(PRICING_MODE)).optional(),
    // Filters (SCRUM-69). Prices are the seat price for the passenger's segment, in LKR cents.
    maxPriceCents: z.coerce.number().int().min(0).optional(),
    departAfter: clockTime.optional(),
    departBefore: clockTime.optional(),
    minCargoKg: z.coerce.number().positive().max(2000).optional(),
    // Only "true" is accepted: z.coerce.boolean() would read "false" as true.
    allowsCargo: z
      .literal('true')
      .transform(() => true)
      .optional(),
    sort: z.enum(Object.values(SEARCH_SORT)).default(SEARCH_SORT.EARLIEST),
    page: z.coerce.number().int().min(1).default(1),
    limit: z.coerce.number().int().min(1).max(50).default(20),
  })
  .refine((q) => !q.departAfter || !q.departBefore || q.departAfter < q.departBefore, {
    message: 'departAfter must be before departBefore',
    path: ['departAfter'],
  });

const myTripsQuery = z.strictObject({
  status: z.enum(Object.values(TRIP_STATUS)).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

const availabilityQuery = z.strictObject({
  fromStop: z.coerce.number().int().min(0),
  toStop: z.coerce.number().int().min(1),
});

const savedRoute = z.strictObject({
  name: z.string().trim().min(2).max(80),
  stops: z.array(stop.omit({ plannedAt: true })).min(TRIP_RULES.MIN_STOPS).max(TRIP_RULES.MAX_STOPS),
});

const savedRouteIdParams = z.strictObject({ id: z.uuid() });

module.exports = {
  createTrip,
  updateTrip,
  tripIdParams,
  cancelTrip,
  searchQuery,
  myTripsQuery,
  availabilityQuery,
  savedRoute,
  savedRouteIdParams,
};
