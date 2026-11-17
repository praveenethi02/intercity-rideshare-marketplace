const crypto = require('node:crypto');
const db = require('../../db');
const ApiError = require('../../utils/ApiError');
const { ROLES } = require('../users/user.constants');
const { reserveSeats, releaseSeats, getSegmentAvailability, PRICING_MODE, TRIP_STATUS } = require('../trips');
const repo = require('./booking.repository');
const { BOOKING_STATUS, BOOKING_RULES } = require('./booking.constants');

const PG_UNIQUE_VIOLATION = '23505';
const ONE_CONFIRMED_INDEX = 'bookings_one_confirmed_per_trip_idx';

const tripNotFound = () => new ApiError(404, 'TRIP_NOT_FOUND', 'Trip not found');
const bookingNotFound = () => new ApiError(404, 'BOOKING_NOT_FOUND', 'Booking not found');
const alreadyBooked = () =>
  new ApiError(409, 'ALREADY_BOOKED', 'You already have a booking on this trip. Cancel it to book again');

// ---------- API shape ----------

function toBooking(row) {
  return {
    id: row.id,
    reference: row.reference,
    status: row.status,
    tripId: row.trip_id,
    passengerId: row.passenger_user_id,
    fromStop: row.from_stop,
    toStop: row.to_stop,
    seats: row.seats,
    pricePerSeatCents: row.price_per_seat_cents,
    totalCents: row.total_cents,
    cancelReason: row.cancel_reason,
    createdAt: row.created_at,
    cancelledAt: row.cancelled_at,
    pickup: { stopOrder: row.from_stop, name: row.pickup_name, plannedAt: row.pickup_at },
    drop: { stopOrder: row.to_stop, name: row.drop_name, plannedAt: row.drop_at },
    trip: {
      id: row.trip_id,
      driverId: row.driver_user_id,
      pricingMode: row.pricing_mode,
      status: row.trip_status,
      originName: row.origin_name,
      destinationName: row.destination_name,
      departureAt: row.departure_at,
      estimatedArrivalAt: row.estimated_arrival_at,
    },
  };
}

// ---------- helpers ----------

function randomReference() {
  const { REFERENCE_PREFIX, REFERENCE_LENGTH, REFERENCE_ALPHABET } = BOOKING_RULES;
  let code = '';
  for (let i = 0; i < REFERENCE_LENGTH; i += 1) {
    code += REFERENCE_ALPHABET[crypto.randomInt(REFERENCE_ALPHABET.length)];
  }
  return REFERENCE_PREFIX + code;
}

/** A reference no booking has yet. 32^6 codes, so a second try is already very rare. */
async function newReference(client) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const reference = randomReference();
    if (!(await repo.referenceExists(reference, client))) return reference;
  }
  throw new Error('Could not generate a unique booking reference');
}

/** The rules that do not need a lock. Seats and trip status are checked again by reserveSeats. */
async function checkBookable(passenger, tripId) {
  const trip = await repo.findTrip(tripId);
  if (!trip || trip.status === TRIP_STATUS.DRAFT) throw tripNotFound();
  if (trip.pricing_mode === PRICING_MODE.AUCTION) {
    throw new ApiError(409, 'AUCTION_TRIP', 'This trip sells seats by auction. Place a bid instead');
  }
  if (trip.driver_user_id === passenger.id) {
    throw new ApiError(403, 'OWN_TRIP', 'You cannot book a seat on your own trip');
  }
  if (trip.status !== TRIP_STATUS.SCHEDULED) {
    throw new ApiError(409, 'TRIP_NOT_BOOKABLE', 'Seats can only be reserved on a published trip');
  }
  if (new Date(trip.departure_at) <= new Date()) {
    throw new ApiError(409, 'TRIP_DEPARTED', 'This trip has already left');
  }
  if (await repo.findConfirmed(tripId, passenger.id)) throw alreadyBooked();
  return trip;
}

// ---------- bookings ----------

async function getBooking(id, viewer) {
  const row = await repo.findById(id);
  if (!row) throw bookingNotFound();
  const canSee =
    viewer.role === ROLES.ADMIN || viewer.id === row.passenger_user_id || viewer.id === row.driver_user_id;
  // Others get 404, not 403, so they cannot tell which booking ids exist.
  if (!canSee) throw bookingNotFound();
  return toBooking(row);
}

/**
 * Books seats on a FIXED-price trip. The seat price comes from the trip (getSegmentAvailability),
 * never from the client. The seats and the booking are saved in one transaction.
 */
async function createBooking(passenger, { tripId, fromStop, toStop, seats }) {
  const trip = await checkBookable(passenger, tripId);
  // 422 INVALID_SEGMENT for stops that are not on the trip. Runs outside the transaction because
  // it reads with the shared db.
  const { segmentPriceCents } = await getSegmentAvailability(tripId, fromStop, toStop);

  const bookingId = await db.transaction(async (tx) => {
    // Locks the trip and its legs, re-checks SCHEDULED and seats: 409 NOT_ENOUGH_SEATS.
    await reserveSeats(tx, tripId, fromStop, toStop, seats);

    // The trip is locked now, so its price cannot change until we commit. If the driver changed
    // it after we read the segment price, stop rather than charge an old price.
    const locked = await repo.findTrip(tripId, tx);
    if (locked.base_price_cents !== trip.base_price_cents) {
      throw new ApiError(409, 'PRICE_CHANGED', 'The driver just changed the price. Check the new price and try again');
    }

    try {
      const row = await repo.insert(
        {
          reference: await newReference(tx),
          tripId,
          passengerUserId: passenger.id,
          fromStop,
          toStop,
          seats,
          pricePerSeatCents: segmentPriceCents,
          totalCents: seats * segmentPriceCents,
        },
        tx,
      );
      return row.id;
    } catch (error) {
      // Two requests at once from the same passenger: the unique index lets only one through.
      if (error.code === PG_UNIQUE_VIOLATION && String(error.constraint ?? error.message).includes(ONE_CONFIRMED_INDEX)) {
        throw alreadyBooked();
      }
      throw error;
    }
  });
  return getBooking(bookingId, passenger);
}

async function listMyBookings(passenger, query) {
  const { bookings, total } = await repo.listForPassenger(passenger.id, query);
  return { bookings: bookings.map(toBooking), total };
}

/** Only the passenger, and only while the trip is SCHEDULED. Gives the seats back. */
async function cancelBooking(passenger, id, reason) {
  await db.transaction(async (tx) => {
    const booking = await repo.lock(id, tx);
    if (!booking || booking.passenger_user_id !== passenger.id) throw bookingNotFound();
    if (booking.status === BOOKING_STATUS.CANCELLED) {
      throw new ApiError(409, 'ALREADY_CANCELLED', 'This booking is already cancelled');
    }

    // releaseSeats locks the trip first, so its status cannot change while we check it below.
    // If the check fails, the transaction rolls the seats back.
    await releaseSeats(tx, booking.trip_id, booking.from_stop, booking.to_stop, booking.seats);
    const trip = await repo.findTrip(booking.trip_id, tx);
    if (trip.status !== TRIP_STATUS.SCHEDULED) {
      throw new ApiError(409, 'TRIP_NOT_CANCELLABLE', `A booking on a ${trip.status} trip cannot be cancelled`);
    }

    await repo.cancel(id, reason, tx);
  });
  return getBooking(id, passenger);
}

module.exports = { getBooking, createBooking, listMyBookings, cancelBooking };
