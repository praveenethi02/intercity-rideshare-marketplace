const db = require('../../db');
const ApiError = require('../../utils/ApiError');
const { ROLES } = require('../users/user.constants');
const repo = require('./trip.repository');
const integrations = require('./trip.integrations');
const { TRIP_STATUS, TRIP_RULES } = require('./trip.constants');
const { withDistanceFromStart, haversineKm, boundingBox } = require('./geo');
const { legsFor, availableSeats, segmentPriceCents } = require('./segments');
const { canTransition, editableFields } = require('./trip-lifecycle');

const MINUTE = 60_000;
const DAY = 86_400_000;
const km = (metres) => Math.round(metres / 100) / 10; // 1 decimal
const round1 = (x) => Math.round(x * 10) / 10;

const tripNotFound = () => new ApiError(404, 'TRIP_NOT_FOUND', 'Trip not found');

// ---------- API shapes ----------

function toStop(row) {
  return {
    order: row.stop_order,
    name: row.name,
    lat: row.lat,
    lng: row.lng,
    distanceFromStartKm: km(row.distance_from_start_m),
    plannedAt: row.planned_at,
  };
}

/** Trip for the API. Pass stops and legSeats for the detail view. */
function toTrip(row, stops, legSeats) {
  const trip = {
    id: row.id,
    driverId: row.driver_user_id,
    vehicleId: row.vehicle_id,
    pricingMode: row.pricing_mode,
    status: row.status,
    originName: row.origin_name,
    destinationName: row.destination_name,
    departureAt: row.departure_at,
    estimatedArrivalAt: row.estimated_arrival_at,
    seatsOffered: row.seats_offered,
    seatsAvailable: row.seats_available,
    basePriceCents: row.base_price_cents,
    distanceKm: km(row.distance_m),
    allowsCargo: row.allows_cargo,
    cargoCapacityKg: row.cargo_capacity_kg,
    notes: row.notes,
    cancelReason: row.cancel_reason,
    publishedAt: row.published_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    cancelledAt: row.cancelled_at,
    createdAt: row.created_at,
  };
  if (stops) trip.stops = stops.map(toStop);
  if (legSeats) {
    trip.legs = legSeats.map((reserved, legIndex) => ({
      legIndex,
      seatsReserved: reserved,
      seatsAvailable: Math.max(0, row.seats_offered - reserved),
    }));
  }
  return trip;
}

function toSavedRoute(row) {
  return { id: row.id, name: row.name, stops: row.stops, createdAt: row.created_at };
}

// ---------- rules ----------

function checkDeparture(departureAt) {
  const departure = new Date(departureAt).getTime();
  const now = Date.now();
  if (departure < now + TRIP_RULES.MIN_LEAD_MINUTES * MINUTE) {
    throw new ApiError(
      422,
      'DEPARTURE_TOO_SOON',
      `Departure must be at least ${TRIP_RULES.MIN_LEAD_MINUTES} minutes from now`,
    );
  }
  if (departure > now + TRIP_RULES.MAX_DAYS_AHEAD * DAY) {
    throw new ApiError(
      422,
      'DEPARTURE_TOO_FAR',
      `Departure cannot be more than ${TRIP_RULES.MAX_DAYS_AHEAD} days ahead`,
    );
  }
}

function checkArrival(estimatedArrivalAt, departureAt) {
  if (estimatedArrivalAt && new Date(estimatedArrivalAt) <= new Date(departureAt)) {
    throw new ApiError(422, 'INVALID_ARRIVAL', 'Estimated arrival must be after departure');
  }
}

/** Validates stop order and adds distance_from_start_m. */
function prepareStops(stops, departureAt) {
  for (let i = 1; i < stops.length; i += 1) {
    if (haversineKm(stops[i - 1], stops[i]) < TRIP_RULES.MIN_STOP_GAP_KM) {
      throw new ApiError(422, 'INVALID_STOPS', `Stop ${i} (${stops[i].name}) is too close to the previous stop`);
    }
    const previous = stops[i - 1].plannedAt || departureAt;
    if (stops[i].plannedAt && new Date(stops[i].plannedAt) <= new Date(previous)) {
      throw new ApiError(422, 'INVALID_STOPS', `The planned time of stop ${i} must be after the previous stop`);
    }
  }
  const prepared = withDistanceFromStart(stops);
  prepared[0] = { ...prepared[0], plannedAt: prepared[0].plannedAt || departureAt };
  return prepared;
}

function routeFields(stops) {
  return {
    originName: stops[0].name,
    destinationName: stops[stops.length - 1].name,
    distanceM: stops[stops.length - 1].distance_from_start_m,
  };
}

function assertOwner(trip, user) {
  if (user.role === ROLES.ADMIN) return;
  if (trip.driver_user_id !== user.id) {
    throw new ApiError(403, 'NOT_TRIP_OWNER', 'This trip belongs to another driver');
  }
}

// ---------- trips ----------

async function getTrip(id, viewer) {
  const row = await repo.findById(id);
  if (!row) throw tripNotFound();
  const isOwner = viewer && (viewer.id === row.driver_user_id || viewer.role === ROLES.ADMIN);
  if (row.status === TRIP_STATUS.DRAFT && !isOwner) throw tripNotFound();
  const [stops, legSeats] = await Promise.all([repo.findStops(id), repo.findLegSeats(id)]);
  return toTrip(row, stops, legSeats);
}

async function createTrip(driver, input) {
  checkDeparture(input.departureAt);
  checkArrival(input.estimatedArrivalAt, input.departureAt);
  const stops = prepareStops(input.stops, input.departureAt);

  const tripId = await db.transaction(async (tx) => {
    await integrations.assertDriverEligible(driver.id, tx);
    await integrations.assertVehicleUsable(driver.id, input.vehicleId, input.seatsOffered, tx);
    const row = await repo.insertTrip({ ...input, ...routeFields(stops), driverUserId: driver.id }, tx);
    await repo.replaceStops(row.id, stops, tx);
    return row.id;
  });
  return getTrip(tripId, driver);
}

async function updateTrip(user, id, changes) {
  await db.transaction(async (tx) => {
    const trip = await repo.lock(id, tx);
    if (!trip) throw tripNotFound();
    assertOwner(trip, user);

    const reserved = await repo.maxSeatsReserved(id, tx);
    const allowed = editableFields(trip.status, reserved > 0);
    if (allowed !== 'ALL') {
      const blocked = Object.keys(changes).filter((field) => !allowed.includes(field));
      if (blocked.length > 0) {
        const why = reserved > 0 ? ' because seats are reserved' : '';
        throw new ApiError(409, 'TRIP_LOCKED', `You cannot change ${blocked.join(', ')} on a ${trip.status} trip${why}`, {
          editable: allowed,
        });
      }
    }

    const departureAt = changes.departureAt ?? trip.departure_at.toISOString();
    if (changes.departureAt) checkDeparture(changes.departureAt);
    checkArrival(changes.estimatedArrivalAt ?? trip.estimated_arrival_at, departureAt);

    const seatsOffered = changes.seatsOffered ?? trip.seats_offered;
    if (changes.seatsOffered !== undefined) {
      await integrations.assertVehicleUsable(trip.driver_user_id, trip.vehicle_id, seatsOffered, tx);
    }

    const allowsCargo = changes.allowsCargo ?? trip.allows_cargo;
    const cargoCapacityKg = changes.cargoCapacityKg ?? trip.cargo_capacity_kg;
    if (allowsCargo && !cargoCapacityKg) {
      throw new ApiError(422, 'CARGO_CAPACITY_REQUIRED', 'cargoCapacityKg is required when allowsCargo is true');
    }

    const { stops: newStops, ...fields } = changes;
    if (newStops) {
      const stops = prepareStops(newStops, departureAt);
      Object.assign(fields, routeFields(stops));
      await repo.replaceStops(id, stops, tx);
    }
    if (changes.allowsCargo === false) fields.cargoCapacityKg = null;
    // Set together with seatsOffered so the seats_available <= seats_offered check holds.
    if (changes.seatsOffered !== undefined) fields.seatsAvailable = Math.max(0, seatsOffered - reserved);
    await repo.update(id, fields, tx);
    await repo.refreshSeatsAvailable(id, tx);
  });
  return getTrip(id, user);
}

async function changeStatus(user, id, to, { reason } = {}) {
  const updated = await db.transaction(async (tx) => {
    const trip = await repo.lock(id, tx);
    if (!trip) throw tripNotFound();
    assertOwner(trip, user);
    if (!canTransition(trip.status, to)) {
      throw new ApiError(409, 'INVALID_STATUS_CHANGE', `A ${trip.status} trip cannot become ${to}`);
    }

    const now = new Date();
    const fields = { status: to };
    if (to === TRIP_STATUS.SCHEDULED) {
      if (trip.departure_at <= now) throw new ApiError(409, 'DEPARTURE_PASSED', 'The departure time has passed');
      fields.publishedAt = now;
    }
    if (to === TRIP_STATUS.IN_PROGRESS) {
      if (trip.departure_at.getTime() - now.getTime() > TRIP_RULES.START_WINDOW_MINUTES * MINUTE) {
        throw new ApiError(
          409,
          'TOO_EARLY_TO_START',
          `You can start at most ${TRIP_RULES.START_WINDOW_MINUTES} minutes before departure`,
        );
      }
      fields.startedAt = now;
    }
    if (to === TRIP_STATUS.COMPLETED) fields.completedAt = now;
    if (to === TRIP_STATUS.CANCELLED) {
      fields.cancelledAt = now;
      fields.cancelReason = reason;
    }
    return repo.update(id, fields, tx);
  });
  if (to === TRIP_STATUS.CANCELLED) await integrations.onTripCancelled(updated);
  return getTrip(id, user);
}

const publishTrip = (user, id) => changeStatus(user, id, TRIP_STATUS.SCHEDULED);
const startTrip = (user, id) => changeStatus(user, id, TRIP_STATUS.IN_PROGRESS);
const completeTrip = (user, id) => changeStatus(user, id, TRIP_STATUS.COMPLETED);
const cancelTrip = (user, id, reason) => changeStatus(user, id, TRIP_STATUS.CANCELLED, { reason });

async function listMyTrips(driver, query) {
  const { trips, total } = await repo.listForDriver(driver.id, query);
  return { trips: trips.map((row) => toTrip(row)), total };
}

// ---------- search (route-segment matching) ----------

/** Start and end of a Sri Lankan calendar day as ISO strings. */
function dayRange(date) {
  const start = new Date(`${date}T00:00:00${TRIP_RULES.TIME_ZONE_OFFSET}`);
  return { dayStart: start.toISOString(), dayEnd: new Date(start.getTime() + DAY).toISOString() };
}

async function searchTrips(query) {
  const from = { lat: query.fromLat, lng: query.fromLng };
  const to = { lat: query.toLat, lng: query.toLng };
  const { radiusKm } = query;

  const candidates = await repo.searchCandidates({
    fromBox: boundingBox(from, radiusKm),
    toBox: boundingBox(to, radiusKm),
    ...dayRange(query.date),
    pricingMode: query.pricingMode ?? null,
  });

  // Keep the closest pickup/drop pair for each trip.
  const best = new Map();
  for (const c of candidates) {
    const pickupKm = haversineKm(from, { lat: c.from_lat, lng: c.from_lng });
    const dropKm = haversineKm(to, { lat: c.to_lat, lng: c.to_lng });
    if (pickupKm > radiusKm || dropKm > radiusKm) continue;
    const current = best.get(c.trip_id);
    if (!current || pickupKm + dropKm < current.pickupKm + current.dropKm) {
      best.set(c.trip_id, { ...c, pickupKm, dropKm });
    }
  }

  const legsByTrip = await repo.findLegSeatsForTrips([...best.keys()]);
  const results = [];
  for (const c of best.values()) {
    const seatsAvailable = availableSeats(c.seats_offered, legsByTrip.get(c.trip_id) || [], c.from_order, c.to_order);
    if (seatsAvailable < query.seats) continue;
    results.push({
      tripId: c.trip_id,
      driverId: c.driver_user_id,
      vehicleId: c.vehicle_id,
      pricingMode: c.pricing_mode,
      departureAt: c.departure_at,
      allowsCargo: c.allows_cargo,
      pickup: {
        stopOrder: c.from_order,
        name: c.from_name,
        lat: c.from_lat,
        lng: c.from_lng,
        plannedAt: c.from_at,
        distanceFromYouKm: round1(c.pickupKm),
      },
      drop: {
        stopOrder: c.to_order,
        name: c.to_name,
        lat: c.to_lat,
        lng: c.to_lng,
        plannedAt: c.to_at,
        distanceFromYourDestinationKm: round1(c.dropKm),
      },
      segmentDistanceKm: km(c.to_m - c.from_m),
      seatsAvailable,
      // FIXED: the seat price for this segment. AUCTION: the suggested starting bid.
      segmentPriceCents: segmentPriceCents(c.base_price_cents, c.distance_m, c.from_m, c.to_m),
    });
  }

  results.sort(
    (a, b) =>
      new Date(a.departureAt) - new Date(b.departureAt) ||
      a.pickup.distanceFromYouKm + a.drop.distanceFromYourDestinationKm -
        (b.pickup.distanceFromYouKm + b.drop.distanceFromYourDestinationKm),
  );
  const start = (query.page - 1) * query.limit;
  return { results: results.slice(start, start + query.limit), total: results.length };
}

async function getSegmentAvailability(id, fromStop, toStop) {
  const trip = await repo.findById(id);
  if (!trip || trip.status === TRIP_STATUS.DRAFT) throw tripNotFound();
  const stops = await repo.findStops(id);
  if (toStop >= stops.length || toStop <= fromStop) {
    throw new ApiError(422, 'INVALID_SEGMENT', `Choose stops between 0 and ${stops.length - 1}, drop after pickup`);
  }
  const legSeats = await repo.findLegSeats(id);
  return {
    tripId: id,
    fromStop,
    toStop,
    seatsAvailable: availableSeats(trip.seats_offered, legSeats, fromStop, toStop),
    segmentPriceCents: segmentPriceCents(
      trip.base_price_cents,
      trip.distance_m,
      stops[fromStop].distance_from_start_m,
      stops[toStop].distance_from_start_m,
    ),
  };
}

// ---------- seat holds: for the Booking and Auction modules ----------

/**
 * Holds seats on the legs between two stops. Call it with the transaction your module uses to
 * save the booking, so both are saved together or not at all:
 *   await db.transaction(async (tx) => { await reserveSeats(tx, tripId, 1, 3, 2); ... });
 */
async function reserveSeats(tx, tripId, fromStop, toStop, seats) {
  const trip = await repo.lock(tripId, tx);
  if (!trip) throw tripNotFound();
  if (trip.status !== TRIP_STATUS.SCHEDULED) {
    throw new ApiError(409, 'TRIP_NOT_BOOKABLE', 'Seats can only be reserved on a published trip');
  }
  let legs;
  try {
    legs = legsFor(fromStop, toStop);
  } catch (error) {
    throw new ApiError(422, 'INVALID_SEGMENT', error.message);
  }
  const locked = await repo.lockLegs(tripId, fromStop, toStop, tx);
  if (locked.length !== legs.length) throw new ApiError(422, 'INVALID_SEGMENT', 'The stops are not on this trip');
  const busiest = Math.max(...locked.map((leg) => leg.seats_reserved));
  if (busiest + seats > trip.seats_offered) {
    throw new ApiError(409, 'NOT_ENOUGH_SEATS', 'Not enough seats on this part of the route', {
      seatsAvailable: trip.seats_offered - busiest,
    });
  }
  await repo.addToLegs(tripId, fromStop, toStop, seats, tx);
  await repo.refreshSeatsAvailable(tripId, tx);
  return { tripId, fromStop, toStop, seats };
}

/** Gives seats back (cancelled booking, refund, unpaid auction win). Use inside a transaction. */
async function releaseSeats(tx, tripId, fromStop, toStop, seats) {
  await repo.lock(tripId, tx);
  const locked = await repo.lockLegs(tripId, fromStop, toStop, tx);
  if (locked.length === 0 || locked.some((leg) => leg.seats_reserved < seats)) {
    throw new ApiError(409, 'RELEASE_MISMATCH', 'Cannot release more seats than are reserved');
  }
  await repo.addToLegs(tripId, fromStop, toStop, -seats, tx);
  await repo.refreshSeatsAvailable(tripId, tx);
}

// ---------- saved routes ----------

async function createSavedRoute(driver, { name, stops }) {
  try {
    return toSavedRoute(await repo.insertSavedRoute(driver.id, name, stops));
  } catch (error) {
    if (error.code === '23505') {
      throw new ApiError(409, 'ROUTE_NAME_TAKEN', 'You already have a saved route with this name');
    }
    throw error;
  }
}

async function listSavedRoutes(driver) {
  return (await repo.listSavedRoutes(driver.id)).map(toSavedRoute);
}

async function deleteSavedRoute(driver, id) {
  if (!(await repo.deleteSavedRoute(driver.id, id))) {
    throw new ApiError(404, 'SAVED_ROUTE_NOT_FOUND', 'Saved route not found');
  }
}

module.exports = {
  getTrip,
  createTrip,
  updateTrip,
  publishTrip,
  startTrip,
  completeTrip,
  cancelTrip,
  listMyTrips,
  searchTrips,
  getSegmentAvailability,
  reserveSeats,
  releaseSeats,
  createSavedRoute,
  listSavedRoutes,
  deleteSavedRoute,
};
