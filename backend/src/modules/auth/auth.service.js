const crypto = require('node:crypto');
const db = require('../../db');
const env = require('../../config/env');
const ApiError = require('../../utils/ApiError');
const { hashPassword, verifyPassword } = require('../../utils/password');
const userRepository = require('../users/user.repository');
const { USER_STATUS } = require('../users/user.constants');
const sessionRepository = require('./session.repository');
const tokens = require('./token.service');
const otpService = require('./otp.service');

const { OTP_PURPOSE } = otpService;
const CAN_RESET_PASSWORD = [USER_STATUS.ACTIVE, USER_STATUS.DEACTIVATED];

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

/**
 * Creates an unverified account and texts a code to the phone. An account nobody has verified
 * can be registered again, so a stranger who enters your number cannot lock you out of it.
 */
async function register({ fullName, phone, email, password, role }) {
  const existing = await userRepository.findByPhone(phone);
  if (existing && existing.status !== USER_STATUS.PENDING_VERIFICATION) {
    throw new ApiError(409, 'PHONE_ALREADY_REGISTERED', 'This phone number is already registered');
  }

  const passwordHash = await hashPassword(password);

  if (existing) {
    await otpService.issue(phone, OTP_PURPOSE.REGISTER);
    return userRepository.updatePendingRegistration(existing.id, {
      fullName,
      email,
      passwordHash,
      role,
    });
  }

  const user = await userRepository.create({
    fullName,
    phone,
    email,
    passwordHash,
    role,
    status: USER_STATUS.PENDING_VERIFICATION,
  });
  await otpService.issue(phone, OTP_PURPOSE.REGISTER);
  return user;
}

/** Confirms the registration code, activates the account and signs the user in. */
async function verifyPhone({ phone, otp }) {
  const pending = await userRepository.findByPhone(phone);
  if (pending?.status !== USER_STATUS.PENDING_VERIFICATION) throw otpService.invalidOtp();

  await otpService.consume(phone, OTP_PURPOSE.REGISTER, otp);

  return db.transaction(async (tx) => {
    const user = await userRepository.markPhoneVerified(pending.id, tx);
    if (!user) throw otpService.invalidOtp();
    return { user, tokens: await startSession(user, tx) };
  });
}

/** Sends a new registration code. The response does not reveal whether the account exists. */
async function resendRegistrationOtp({ phone }) {
  const user = await userRepository.findByPhone(phone);
  if (user?.status === USER_STATUS.PENDING_VERIFICATION) {
    await otpService.issue(phone, OTP_PURPOSE.REGISTER);
  }
}

/** Sends a password reset code. The response does not reveal whether the account exists. */
async function forgotPassword({ phone }) {
  const user = await userRepository.findByPhone(phone);
  if (user && CAN_RESET_PASSWORD.includes(user.status)) {
    await otpService.issue(phone, OTP_PURPOSE.PASSWORD_RESET);
  }
}

/** Sets a new password using a reset code and signs out every device. */
async function resetPassword({ phone, otp, newPassword }) {
  const user = await userRepository.findByPhone(phone);
  if (!user || !CAN_RESET_PASSWORD.includes(user.status)) throw otpService.invalidOtp();

  await otpService.consume(phone, OTP_PURPOSE.PASSWORD_RESET, otp);

  const passwordHash = await hashPassword(newPassword);
  await db.transaction(async (tx) => {
    await userRepository.updatePassword(user.id, passwordHash, tx);
    await sessionRepository.revokeAllForUser(user.id, {}, tx);
  });
}

/** Changes the password of a signed-in user and signs out their other devices. */
async function changePassword(user, sessionId, { currentPassword, newPassword }) {
  if (!(await verifyPassword(currentPassword, user.password_hash))) {
    throw new ApiError(400, 'INCORRECT_PASSWORD', 'The current password is incorrect');
  }

  const passwordHash = await hashPassword(newPassword);
  await db.transaction(async (tx) => {
    await userRepository.updatePassword(user.id, passwordHash, tx);
    await sessionRepository.revokeAllForUser(user.id, { exceptSessionId: sessionId }, tx);
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

module.exports = {
  assertCanSignIn,
  startSession,
  register,
  verifyPhone,
  resendRegistrationOtp,
  forgotPassword,
  resetPassword,
  changePassword,
  login,
  refresh,
  logout,
  logoutEverywhere,
};
