const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const validate = require('../../middleware/validate');
const respond = require('../../utils/respond');
const { ROLES } = require('../users/user.constants');
const { pageMeta } = require('./driver.routes');
const schemas = require('./driver.schemas');
const verificationService = require('./verification.service');

// Guards each route rather than the whole router, because this router shares the /admin prefix.
const adminOnly = [authenticate, requireRole(ROLES.ADMIN)];

const router = Router();

router.get(
  '/verifications',
  adminOnly,
  validate({ query: schemas.queueQuery }),
  async (req, res) => {
    const { verifications, total } = await verificationService.listQueue(req.validated.query);
    return respond(res, {
      message: 'Verification queue loaded',
      data: { verifications },
      meta: pageMeta(req.validated.query, total),
    });
  },
);

router.patch(
  '/verifications/:id',
  adminOnly,
  validate({ params: schemas.verificationIdParams, body: schemas.decision }),
  async (req, res) => {
    const verification = await verificationService.decide(
      req.user,
      req.validated.params.id,
      req.validated.body,
    );
    return respond(res, { message: 'Decision saved', data: { verification } });
  },
);

router.patch(
  '/drivers/:id/account-status',
  adminOnly,
  validate({ params: schemas.driverIdParams, body: schemas.accountStatus }),
  async (req, res) => {
    const driver = await verificationService.setAccountStatus(
      req.user,
      req.validated.params.id,
      req.validated.body,
    );
    return respond(res, { message: 'Driver account status updated', data: { driver } });
  },
);

module.exports = router;
