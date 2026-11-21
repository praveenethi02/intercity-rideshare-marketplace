// What other modules may use from ratings.
const ratingRoutes = require('./rating.routes');
const { RATER_ROLE } = require('./rating.constants');

module.exports = { ratingRoutes, RATER_ROLE };
