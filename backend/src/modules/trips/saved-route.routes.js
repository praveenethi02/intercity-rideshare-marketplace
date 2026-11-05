const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const { authRateLimit } = require('../../middleware/rate-limit');
const validate = require('../../middleware/validate');
const respond = require('../../utils/respond');
const { ROLES } = require('../users/user.constants');
const schemas = require('./trip.schemas');
const tripService = require('./trip.service');

const router = Router();

router.use(authRateLimit, authenticate, requireRole(ROLES.DRIVER));

router.get('/', async (req, res) => {
  const savedRoutes = await tripService.listSavedRoutes(req.user);
  return respond(res, { message: 'Saved routes loaded', data: { savedRoutes } });
});

router.post('/', validate({ body: schemas.savedRoute }), async (req, res) => {
  const savedRoute = await tripService.createSavedRoute(req.user, req.validated.body);
  return respond(res, { status: 201, message: 'Route saved', data: { savedRoute } });
});

router.delete('/:id', validate({ params: schemas.savedRouteIdParams }), async (req, res) => {
  await tripService.deleteSavedRoute(req.user, req.validated.params.id);
  return respond(res, { message: 'Saved route deleted' });
});

module.exports = router;
