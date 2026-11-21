const { rateLimit } = require('express-rate-limit');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');

/** A per-IP limit. Each limit keeps its own count, so one cannot use up another. */
function perIpLimit({ windowMinutes, max, message }) {
  return rateLimit({
    windowMs: windowMinutes * 60 * 1000,
    limit: max,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    skip: () => !env.RATE_LIMIT_ENABLED,
    handler: (req, res, next) => {
      next(new ApiError(429, 'TOO_MANY_REQUESTS', message));
    },
  });
}

/** Strict limit for the auth endpoints, to slow down password and OTP guessing. */
const authRateLimit = perIpLimit({
  windowMinutes: env.AUTH_RATE_LIMIT_WINDOW_MINUTES,
  max: env.AUTH_RATE_LIMIT_MAX,
  message: 'Too many attempts. Please try again later.',
});

/** Looser limit for everyday app requests: trips, saved routes and bookings. */
const apiRateLimit = perIpLimit({
  windowMinutes: env.API_RATE_LIMIT_WINDOW_MINUTES,
  max: env.API_RATE_LIMIT_MAX,
  message: 'Too many requests. Please wait a moment and try again.',
});

module.exports = { authRateLimit, apiRateLimit };