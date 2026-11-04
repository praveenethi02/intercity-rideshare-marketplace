const crypto = require('node:crypto');
const env = require('../../config/env');
const ApiError = require('../../utils/ApiError');
const { hashPassword, verifyPassword } = require('../../utils/password');
const userRepository = require('../users/user.repository');
const { USER_STATUS } = require('../users/user.constants');
const sessionRepository = require('./session.repository');
const tokens = require('./token.service');

const invalidCredentials = () =>
  new ApiError(401, 'INVALID_CREDENTIALS', 'Incorrect phone number or password');

const invalidRefreshToken = () =>
  new ApiError(401, 'INVALID_REFRESH_TOKEN', 'Refresh token is invalid or expired');

function assertCanSignIn(user) {
  if (user.status === USER_STATUS.ACTIVE) return;

  const reasons = {
    [USER_STATUS.PENDING_VERIFICATION]: ['PHONE_NOT_VERIFIED', 'Verify your phone number first'],
    [USER_STATUS.DEACTIVATED]: ['ACCOUNT_DEACTIVATED', 'This account has been deactivated'],
    [USER_STATUS.SUSPENDED]: ['ACCOUNT_SUSPENDED', 'This account has been suspended'],
  };
  const [code, message] = reasons[user.status];
  throw new ApiError(403, code, message);
}

async function startSession(user, client) {
  const sessionId = crypto.randomUUID();
  const refresh = tokens.generateRefreshToken(sessionId);

  await sessionRepository.create(
    { id: sessionId, userId: user.id, refreshTokenHash: refresh.hash },
    client,
  );

  return {
    accessToken: tokens.signAccessToken(user.id, sessionId),
    refreshToken: refresh.token,
    tokenType: 'Bearer',
    expiresIn: env.JWT_ACCESS_TTL_SECONDS,
  };
}

async function register({ fullName, phone, email, password, role }) {
  const existing = await userRepository.findByPhone(phone);
  if (existing) {
    throw new ApiError(409, 'PHONE_ALREADY_REGISTERED', 'This phone number is already registered');
  }

  return userRepository.create({
    fullName,
    phone,
    email,
    passwordHash: await hashPassword(password),
    role,
    status: USER_STATUS.ACTIVE,
  });
}

async function login({ phone, password }) {
  const user = await userRepository.findByPhone(phone);
  const passwordIsCorrect = await verifyPassword(password, user?.password_hash);

  if (!user || !passwordIsCorrect) throw invalidCredentials();
  assertCanSignIn(user);

  return { user, tokens: await startSession(user) };
}

/** Exchanges a refresh token for new tokens. Reusing an old token ends the session. */
async function refresh({ refreshToken }) {
  const sessionId = tokens.parseRefreshToken(refreshToken);
  if (!sessionId) throw invalidRefreshToken();

  const session = await sessionRepository.findLive(sessionId);
  if (!session) throw invalidRefreshToken();

  const presentedHash = tokens.hashRefreshToken(refreshToken);
  const reused = !tokens.hashesMatch(presentedHash, session.refresh_token_hash);
  const next = tokens.generateRefreshToken(sessionId);

  if (reused || !(await sessionRepository.rotate(sessionId, presentedHash, next.hash))) {
    await sessionRepository.revoke(sessionId);
    throw invalidRefreshToken();
  }

  const user = await userRepository.findById(session.user_id);
  try {
    assertCanSignIn(user);
  } catch (error) {
    await sessionRepository.revoke(sessionId);
    throw error;
  }

  return {
    accessToken: tokens.signAccessToken(user.id, sessionId),
    refreshToken: next.token,
    tokenType: 'Bearer',
    expiresIn: env.JWT_ACCESS_TTL_SECONDS,
  };
}

const logout = (sessionId) => sessionRepository.revoke(sessionId);

const logoutEverywhere = (userId) => sessionRepository.revokeAllForUser(userId);

module.exports = { assertCanSignIn, startSession, register, login, refresh, logout, logoutEverywhere };
