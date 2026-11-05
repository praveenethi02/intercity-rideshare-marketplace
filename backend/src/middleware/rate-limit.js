const { rateLimit } = require('express-rate-limit');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');

/** Per-IP limit for the auth endpoints, to slow down password and OTP guessing. */
const authRateLimit = rateLimit({
  windowMs: env.AUTH_RATE_LIMIT_WINDOW_MINUTES * 60 * 1000,
  limit: env.AUTH_RATE_LIMIT_MAX,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  skip: () => !env.RATE_LIMIT_ENABLED,
  handler: (req, res, next) => {
    next(new ApiError(429, 'TOO_MANY_REQUESTS', 'Too many attempts. Please try again later.'));
  },
});

module.exports = { authRateLimit };
