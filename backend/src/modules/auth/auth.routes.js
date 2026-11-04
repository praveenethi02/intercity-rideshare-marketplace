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
    message: 'Registration started. Enter the code sent to your phone.',
    data: { user: toPublicUser(user) },
  });
});

router.post('/otp/verify', validate({ body: schemas.verifyPhone }), async (req, res) => {
  const { user, tokens } = await authService.verifyPhone(req.validated.body);
  return respond(res, {
    message: 'Phone number verified',
    data: { user: toPublicUser(user), tokens },
  });
});

router.post('/otp/resend', validate({ body: schemas.phoneOnly }), async (req, res) => {
  await authService.resendRegistrationOtp(req.validated.body);
  return respond(res, { message: 'If the account needs verifying, a new code has been sent' });
});

router.post('/password/forgot', validate({ body: schemas.phoneOnly }), async (req, res) => {
  await authService.forgotPassword(req.validated.body);
  return respond(res, { message: 'If the account exists, a reset code has been sent' });
});

router.post('/password/reset', validate({ body: schemas.resetPassword }), async (req, res) => {
  await authService.resetPassword(req.validated.body);
  return respond(res, { message: 'Password reset. Please log in again.' });
});

router.post(
  '/password/change',
  authenticate,
  validate({ body: schemas.changePassword }),
  async (req, res) => {
    await authService.changePassword(req.user, req.sessionId, req.validated.body);
    return respond(res, { message: 'Password changed' });
  },
);

router.post('/login', validate({ body: schemas.login }), async (req, res) => {
  const { user, tokens } = await authService.login(req.validated.body);
  return respond(res, {
    message: 'Login successful',
    data: { user: toPublicUser(user), tokens },
  });
});

router.post('/reactivate', validate({ body: schemas.login }), async (req, res) => {
  const { user, tokens } = await authService.reactivate(req.validated.body);
  return respond(res, {
    message: 'Account reactivated',
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
