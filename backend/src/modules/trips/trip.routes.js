const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const validate = require('../../middleware/validate');
const { authRateLimit } = require('../../middleware/rate-limit');
const respond = require('../../utils/respond');
const { ROLES } = require('../users/user.constants');
const schemas = require('./trip.schemas');
const tripService = require('./trip.service');

const router = Router();
const driverOnly = requireRole(ROLES.DRIVER);
const driverOrAdmin = requireRole(ROLES.DRIVER, ROLES.ADMIN);
const byId = { params: schemas.tripIdParams };

const pageMeta = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });

router.use(authRateLimit, authenticate);

// Static paths come before /:id so they are not read as a trip id.
router.get('/search', validate({ query: schemas.searchQuery }), async (req, res) => {
  const query = req.validated.query;
  const { results, total } = await tripService.searchTrips(query);
  return respond(res, {
    message: results.length ? 'Trips found' : 'No trips found for this route and date',
    data: { results },
    meta: { ...pageMeta(query, total), radiusKm: query.radiusKm },
  });
});

router.get('/mine', driverOnly, validate({ query: schemas.myTripsQuery }), async (req, res) => {
  const query = req.validated.query;
  const { trips, total } = await tripService.listMyTrips(req.user, query);
  return respond(res, { message: 'Trips loaded', data: { trips }, meta: pageMeta(query, total) });
});

router.post('/', driverOnly, validate({ body: schemas.createTrip }), async (req, res) => {
  const trip = await tripService.createTrip(req.user, req.validated.body);
  return respond(res, { status: 201, message: 'Trip created as a draft', data: { trip } });
});

router.get('/:id', validate(byId), async (req, res) => {
  const trip = await tripService.getTrip(req.validated.params.id, req.user);
  return respond(res, { message: 'Trip loaded', data: { trip } });
});

router.patch('/:id', driverOrAdmin, validate({ ...byId, body: schemas.updateTrip }), async (req, res) => {
  const trip = await tripService.updateTrip(req.user, req.validated.params.id, req.validated.body);
  return respond(res, { message: 'Trip updated', data: { trip } });
});

router.get(
  '/:id/availability',
  validate({ ...byId, query: schemas.availabilityQuery }),
  async (req, res) => {
    const { fromStop, toStop } = req.validated.query;
    const availability = await tripService.getSegmentAvailability(req.validated.params.id, fromStop, toStop);
    return respond(res, { message: 'Availability loaded', data: { availability } });
  },
);

const action = (handler, message) => async (req, res) => {
  const trip = await handler(req.user, req.validated.params.id);
  return respond(res, { message, data: { trip } });
};

router.post('/:id/publish', driverOrAdmin, validate(byId), action(tripService.publishTrip, 'Trip published'));
router.post('/:id/start', driverOnly, validate(byId), action(tripService.startTrip, 'Trip started'));
router.post('/:id/complete', driverOnly, validate(byId), action(tripService.completeTrip, 'Trip completed'));

router.post('/:id/cancel', driverOrAdmin, validate({ ...byId, body: schemas.cancelTrip }), async (req, res) => {
  const trip = await tripService.cancelTrip(req.user, req.validated.params.id, req.validated.body.reason);
  return respond(res, { message: 'Trip cancelled', data: { trip } });
});

module.exports = router;
