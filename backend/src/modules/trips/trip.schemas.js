const { z } = require('zod');
const { TRIP_STATUS, PRICING_MODE, TRIP_RULES } = require('./trip.constants');

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

const searchQuery = z.strictObject({
  fromLat: latitude,
  fromLng: longitude,
  toLat: latitude,
  toLng: longitude,
  date: z.iso.date(),
  seats: z.coerce.number().int().min(1).max(TRIP_RULES.MAX_SEATS).default(1),
  radiusKm: z.coerce.number().min(0.5).max(30).default(TRIP_RULES.DEFAULT_SEARCH_RADIUS_KM),
  pricingMode: z.enum(Object.values(PRICING_MODE)).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
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
