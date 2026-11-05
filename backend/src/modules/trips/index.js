// What other modules may use from trips.
const tripRoutes = require('./trip.routes');
const savedRouteRoutes = require('./saved-route.routes');
const { reserveSeats, releaseSeats, getSegmentAvailability } = require('./trip.service');
const { TRIP_STATUS, PRICING_MODE } = require('./trip.constants');

module.exports = {
  tripRoutes,
  savedRouteRoutes,
  reserveSeats,
  releaseSeats,
  getSegmentAvailability,
  TRIP_STATUS,
  PRICING_MODE,
};
