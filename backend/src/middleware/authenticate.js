const ApiError = require('../utils/ApiError');
const tokenService = require('../modules/auth/token.service');
const sessionRepository = require('../modules/auth/session.repository');
const userRepository = require('../modules/users/user.repository');
const { USER_STATUS } = require('../modules/users/user.constants');

const unauthorized = () =>
  new ApiError(401, 'UNAUTHORIZED', 'A valid access token is required');

/**
 * Requires a valid Bearer token. Sets req.user (from the database, so role and status are
 * always current) and req.sessionId. Signed-out sessions and closed accounts are rejected.
 */
async function authenticate(req, res, next) {
  const [scheme, token] = (req.headers.authorization || '').split(' ');
  if (scheme !== 'Bearer' || !token) throw unauthorized();

  const claims = tokenService.verifyAccessToken(token);
  if (!claims) throw unauthorized();

  const session = await sessionRepository.findLive(claims.sessionId);
  if (!session || session.user_id !== claims.userId) throw unauthorized();

  const user = await userRepository.findById(claims.userId);
  if (!user) throw unauthorized();
  if (user.status !== USER_STATUS.ACTIVE) {
    throw new ApiError(403, 'ACCOUNT_NOT_ACTIVE', 'This account is not active');
  }

  req.user = user;
  req.sessionId = session.id;
  next();
}

module.exports = authenticate;
