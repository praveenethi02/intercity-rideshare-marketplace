const db = require('../../db');
const ApiError = require('../../utils/ApiError');
const { verifyPassword } = require('../../utils/password');
const sessionRepository = require('../auth/session.repository');
const userRepository = require('./user.repository');
const { ROLES, USER_STATUS } = require('./user.constants');

const updateProfile = (user, changes) => userRepository.updateProfile(user.id, changes);

/** Lets a user switch between the selectable roles. Admins keep their role. */
async function selectRole(user, { role }) {
  if (user.role === ROLES.ADMIN) {
    throw new ApiError(403, 'ADMIN_ROLE_LOCKED', 'Admin accounts cannot change role');
  }
  return userRepository.updateRole(user.id, role);
}

/** Closes the user's own account and signs out every device. */
async function deactivate(user, { password }) {
  if (user.role === ROLES.ADMIN) {
    throw new ApiError(403, 'ADMIN_CANNOT_DEACTIVATE', 'Admin accounts cannot deactivate themselves');
  }
  if (!(await verifyPassword(password, user.password_hash))) {
    throw new ApiError(400, 'INCORRECT_PASSWORD', 'The password is incorrect');
  }

  await db.transaction(async (tx) => {
    await userRepository.changeStatus(user.id, USER_STATUS.ACTIVE, USER_STATUS.DEACTIVATED, tx);
    await sessionRepository.revokeAllForUser(user.id, {}, tx);
  });
}

module.exports = { updateProfile, selectRole, deactivate };
