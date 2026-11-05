const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const validate = require('../../middleware/validate');
const respond = require('../../utils/respond');
const { pageMeta } = require('../drivers/driver.routes');
const { ROLES } = require('../users/user.constants');
const schemas = require('./vehicle.schemas');
const vehicleService = require('./vehicle.service');

const router = Router();

router.use(authenticate, requireRole(ROLES.ADMIN));

// SCRUM-55
router.get('/', validate({ query: schemas.adminListQuery }), async (req, res) => {
  const { vehicles, total } = await vehicleService.adminListVehicles(req.validated.query);
  return respond(res, {
    message: 'Vehicles loaded',
    data: vehicles,
    meta: pageMeta(req.validated.query, total),
  });
});

router.get('/:id', validate({ params: schemas.idParams }), async (req, res) => {
  const data = await vehicleService.adminGetVehicle(req.validated.params.id);
  return respond(res, { message: 'Vehicle loaded', data });
});

// SCRUM-55
router.patch(
  '/:id/verification',
  validate({ params: schemas.idParams, body: schemas.adminDecisionBody }),
  async (req, res) => {
    const { body, params } = req.validated;
    const data = await vehicleService.adminDecide(req.user, params.id, body);
    return respond(res, {
      message: body.decision === 'APPROVE' ? 'Vehicle approved' : 'Vehicle rejected',
      data,
    });
  },
);

// SCRUM-56
router.patch(
  '/:id/status',
  validate({ params: schemas.idParams, body: schemas.adminStatusBody }),
  async (req, res) => {
    const { body, params } = req.validated;
    const data = await vehicleService.adminSetStatus(req.user, params.id, body);
    return respond(res, { message: body.isActive ? 'Vehicle activated' : 'Vehicle deactivated', data });
  },
);

module.exports = router;
