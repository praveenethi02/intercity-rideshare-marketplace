// Keep RATER_ROLE the same as the CHECK in migrations/601_create_rating_tables.sql.
const RATER_ROLE = Object.freeze({
  DRIVER: 'DRIVER',
  PASSENGER: 'PASSENGER',
});

const RATING_RULES = Object.freeze({
  MIN_STARS: 1,
  MAX_STARS: 5,
  MAX_REVIEW_LENGTH: 500, // same as the ratings.review CHECK
});

module.exports = { RATER_ROLE, RATING_RULES };
