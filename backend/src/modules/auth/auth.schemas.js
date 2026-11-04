const { z } = require('zod');
const { SELECTABLE_ROLES } = require('../users/user.constants');
const { normalizePhone } = require('../../utils/phone');

const phone = z.string().transform((value, ctx) => {
  const normalized = normalizePhone(value);
  if (!normalized) {
    ctx.addIssue({ code: 'custom', message: 'Enter a valid Sri Lankan mobile number' });
    return z.NEVER;
  }
  return normalized;
});

// bcrypt only uses the first 72 bytes, so longer passwords are rejected rather than truncated.
const newPassword = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .refine((value) => Buffer.byteLength(value) <= 72, 'Password must be at most 72 bytes')
  .refine((value) => /\p{L}/u.test(value) && /\d/.test(value), {
    message: 'Password must contain a letter and a number',
  });

const fullName = z.string().trim().min(2).max(120);
const email = z.string().trim().toLowerCase().email().max(254);
const selectableRole = z.enum(SELECTABLE_ROLES);

const register = z.strictObject({
  fullName,
  phone,
  email: email.optional(),
  password: newPassword,
  role: selectableRole,
});

const login = z.strictObject({
  phone,
  password: z.string().min(1).max(200),
});

const refresh = z.strictObject({
  refreshToken: z.string().min(1).max(200),
});

module.exports = { phone, newPassword, fullName, email, selectableRole, register, login, refresh };
