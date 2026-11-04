const { z } = require('zod');
const { fullName, phone, newPassword } = require('../modules/auth/auth.schemas');
const userRepository = require('../modules/users/user.repository');
const { ROLES, USER_STATUS } = require('../modules/users/user.constants');
const { hashPassword } = require('../utils/password');
const db = require('./index');

const adminDetails = z.object({
  ADMIN_NAME: fullName,
  ADMIN_PHONE: phone,
  ADMIN_PASSWORD: newPassword,
});

/**
 * Creates the admin account, the only way to get the ADMIN role. An existing phone number is
 * left unchanged, so this can run repeatedly and can never promote or overwrite a user.
 * Returns true if an account was created.
 */
async function seedAdmin(env = process.env) {
  const result = adminDetails.safeParse(env);
  if (!result.success) {
    const problems = result.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`);
    throw new Error(`Invalid admin details:\n  ${problems.join('\n  ')}`);
  }
  const { ADMIN_NAME, ADMIN_PHONE, ADMIN_PASSWORD } = result.data;

  if (await userRepository.findByPhone(ADMIN_PHONE)) return false;

  const passwordHash = await hashPassword(ADMIN_PASSWORD);
  await db.transaction(async (tx) => {
    const user = await userRepository.create(
      {
        fullName: ADMIN_NAME,
        phone: ADMIN_PHONE,
        passwordHash,
        role: ROLES.ADMIN,
        status: USER_STATUS.PENDING_VERIFICATION,
      },
      tx,
    );
    await userRepository.markPhoneVerified(user.id, tx);
  });
  return true;
}

module.exports = seedAdmin;
