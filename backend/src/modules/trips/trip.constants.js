const TRIP_STATUS = Object.freeze({
  DRAFT: 'DRAFT',
  SCHEDULED: 'SCHEDULED',
  IN_PROGRESS: 'IN_PROGRESS',
  COMPLETED: 'COMPLETED',
  CANCELLED: 'CANCELLED',
});

const PRICING_MODE = Object.freeze({ AUCTION: 'AUCTION', FIXED: 'FIXED' });

/** Business rules. The mobile app copies these values in trip_draft.dart. */
const TRIP_RULES = Object.freeze({
  MIN_LEAD_MINUTES: 30, // create or move a trip at least 30 minutes before departure
  MAX_DAYS_AHEAD: 60,
  START_WINDOW_MINUTES: 30, // a driver may start up to 30 minutes early
  MIN_STOP_GAP_KM: 0.2, // consecutive stops must not be the same place
  MIN_STOPS: 2,
  MAX_STOPS: 15,
  MAX_SEATS: 14,
  DEFAULT_SEARCH_RADIUS_KM: 5,
  TIME_ZONE_OFFSET: '+05:30', // search dates are Sri Lankan calendar days
});

module.exports = { TRIP_STATUS, PRICING_MODE, TRIP_RULES };
