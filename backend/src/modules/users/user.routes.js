const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const validate = require('../../middleware/validate');
const respond = require('../../utils/respond');
const { toPublicUser } = require('./user.repository');
const schemas = require('./user.schemas');
const userService = require('./user.service');

const router = Router();

router.use(authenticate);

router.get('/me', (req, res) =>
  respond(res, { message: 'Profile loaded', data: { user: toPublicUser(req.user) } }),
);

router.patch('/me', validate({ body: schemas.updateProfile }), async (req, res) => {
  const user = await userService.updateProfile(req.user, req.validated.body);
  return respond(res, { message: 'Profile updated', data: { user: toPublicUser(user) } });
});

router.put('/me/role', validate({ body: schemas.updateRole }), async (req, res) => {
  const user = await userService.selectRole(req.user, req.validated.body);
  return respond(res, { message: 'Role updated', data: { user: toPublicUser(user) } });
});

router.post('/me/deactivate', validate({ body: schemas.deactivate }), async (req, res) => {
  await userService.deactivate(req.user, req.validated.body);
  return respond(res, { message: 'Account deactivated' });
});

module.exports = router;
