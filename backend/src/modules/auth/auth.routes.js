const { Router } = require('express');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/authenticate');
const { authRateLimit } = require('../../middleware/rate-limit');
const respond = require('../../utils/respond');
const { toPublicUser } = require('../users/user.repository');
const schemas = require('./auth.schemas');
const authService = require('./auth.service');

const router = Router();

router.use(authRateLimit);

router.post('/register', validate({ body: schemas.register }), async (req, res) => {
  const user = await authService.register(req.validated.body);
  return respond(res, {
    status: 201,
    message: 'Registration successful',
    data: { user: toPublicUser(user) },
  });
});

router.post('/login', validate({ body: schemas.login }), async (req, res) => {
  const { user, tokens } = await authService.login(req.validated.body);
  return respond(res, {
    message: 'Login successful',
    data: { user: toPublicUser(user), tokens },
  });
});

router.post('/refresh', validate({ body: schemas.refresh }), async (req, res) => {
  const tokens = await authService.refresh(req.validated.body);
  return respond(res, { message: 'Token refreshed', data: { tokens } });
});

router.post('/logout', authenticate, async (req, res) => {
  await authService.logout(req.sessionId);
  return respond(res, { message: 'Logged out' });
});

router.post('/logout-all', authenticate, async (req, res) => {
  await authService.logoutEverywhere(req.user.id);
  return respond(res, { message: 'Logged out from all devices' });
});

module.exports = router;
