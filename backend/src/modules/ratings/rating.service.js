const db = require('../../db');
const ApiError = require('../../utils/ApiError');
const driverRepository = require('../drivers/driver.repository');
const { TRIP_STATUS } = require('../trips');
const repo = require('./rating.repository');
const { RATER_ROLE } = require('./rating.constants');

const PG_UNIQUE_VIOLATION = '23505';
const ONE_PER_TRIP_INDEX = 'ratings_one_per_trip_idx';

// Outsiders get 404, not 403, so they cannot tell which trip ids exist (the same as bookings).
const tripNotFound = () => new ApiError(404, 'TRIP_NOT_FOUND', 'Trip not found');
const alreadyRated = () => new ApiError(409, 'ALREADY_RATED', 'You have already rated this person for this trip');

/** "Nimal Silva" becomes "Nimal S.", the same as public driver profiles. */
function shortName(fullName) {
  const [first, ...rest] = String(fullName ?? '').trim().split(/\s+/);
  return rest.length ? `${first} ${rest.at(-1)[0].toUpperCase()}.` : first;
}

// ---------- API shape ----------

const toRating = (row) => ({
  id: row.id,
  tripId: row.trip_id,
  raterId: row.rater_user_id,
  rateeId: row.ratee_user_id,
  raterRole: row.rater_role,
  stars: row.stars,
  review: row.review,
  createdAt: row.created_at,
});

const toTrip = (row) => ({
  id: row.trip_id,
  originName: row.origin_name,
  destinationName: row.destination_name,
  departureAt: row.departure_at,
  completedAt: row.completed_at,
});

// ---------- ratings ----------

/**
 * SCRUM-125, 126, 129, 130, 134. The rater's role comes from the trip, never from the client.
 * A rating of a driver updates driver_profiles in the same transaction as the insert.
 */
async function createRating(rater, { tripId, rateeId, stars, review }) {
  if (rateeId === rater.id) {
    throw new ApiError(422, 'CANNOT_RATE_SELF', 'You cannot rate yourself');
  }

  const trip = await repo.findTrip(tripId);
  if (!trip) throw tripNotFound();
  const isDriver = trip.driver_user_id === rater.id;
  if (!isDriver && !(await repo.isConfirmedPassenger(tripId, rater.id))) throw tripNotFound();

  if (trip.status !== TRIP_STATUS.COMPLETED) {
    throw new ApiError(409, 'TRIP_NOT_COMPLETED', 'You can rate only after the trip is completed');
  }

  // The driver rates passengers with a CONFIRMED booking. A passenger rates only the driver.
  const rateeOnTrip = isDriver
    ? await repo.isConfirmedPassenger(tripId, rateeId)
    : rateeId === trip.driver_user_id;
  if (!rateeOnTrip) {
    throw new ApiError(
      422,
      'RATEE_NOT_ON_TRIP',
      isDriver ? 'This person was not a passenger on your trip' : 'You can rate only the driver of this trip',
    );
  }

  const raterRole = isDriver ? RATER_ROLE.DRIVER : RATER_ROLE.PASSENGER;
  const row = await db.transaction(async (tx) => {
    let saved;
    try {
      saved = await repo.insert(
        { tripId, raterUserId: rater.id, rateeUserId: rateeId, raterRole, stars, review: review || null },
        tx,
      );
    } catch (error) {
      // Two requests at once: the unique index lets only one through.
      if (error.code === PG_UNIQUE_VIOLATION && String(error.constraint ?? error.message).includes(ONE_PER_TRIP_INDEX)) {
        throw alreadyRated();
      }
      throw error;
    }
    if (raterRole === RATER_ROLE.PASSENGER) {
      // Only an approved driver can publish a trip, so the trip's driver has a profile.
      await driverRepository.addRating(trip.driver_user_id, stars, tx);
    }
    return saved;
  });
  return toRating(row);
}

/** SCRUM-131, 132, 133: ratings a user received, with the average for the same filter. */
async function listReceived(userId, query) {
  if (!(await repo.userExists(userId))) throw new ApiError(404, 'USER_NOT_FOUND', 'User not found');
  const [summary, { ratings, total }] = await Promise.all([
    repo.summaryFor(userId, query),
    repo.listReceived(userId, query),
  ]);
  return {
    averageRating: summary.average_rating,
    ratingCount: summary.rating_count,
    total,
    ratings: ratings.map((row) => ({
      ...toRating(row),
      reviewer: { id: row.rater_user_id, name: shortName(row.other_name) },
      trip: toTrip(row),
    })),
  };
}

/** SCRUM-133: ratings the signed-in user gave. */
async function listMine(user, query) {
  const { ratings, total } = await repo.listGiven(user.id, query);
  return {
    total,
    ratings: ratings.map((row) => ({
      ...toRating(row),
      ratee: { id: row.ratee_user_id, name: shortName(row.other_name) },
      trip: toTrip(row),
    })),
  };
}

/** SCRUM-134: people the signed-in user can still rate on completed trips. */
async function listPending(user) {
  const rows = await repo.listPending(user.id);
  return rows.map((row) => ({
    trip: toTrip(row),
    ratee: { id: row.ratee_id, name: shortName(row.other_name), role: row.ratee_role },
  }));
}

module.exports = { createRating, listReceived, listMine, listPending, shortName };
