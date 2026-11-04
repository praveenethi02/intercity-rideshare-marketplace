const ApiError = require('../utils/ApiError');

/**
 * Allows only the listed roles. Use after authenticate:
 *   router.post('/trips', authenticate, requireRole(ROLES.DRIVER), handler);
 */
function requireRole(...allowedRoles) {
  if (allowedRoles.length === 0) {
    throw new Error('requireRole needs at least one role');
  }

  return (req, res, next) => {
    if (!req.user) {
      throw new ApiError(401, 'UNAUTHORIZED', 'A valid access token is required');
    }
    if (!allowedRoles.includes(req.user.role)) {
      throw new ApiError(403, 'FORBIDDEN', 'You do not have permission to do this');
    }
    next();
  };
}

module.exports = requireRole;
