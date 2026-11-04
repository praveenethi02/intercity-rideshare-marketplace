const { z } = require('zod');
const { fullName, email, selectableRole } = require('../auth/auth.schemas');

const httpsUrl = z
  .string()
  .trim()
  .url()
  .max(2048)
  .refine((value) => value.startsWith('https://'), 'Must be an https URL');

// Phone numbers and roles cannot be changed here, and strict objects reject unknown fields.
const updateProfile = z
  .strictObject({
    fullName: fullName.optional(),
    email: email.nullable().optional(),
    avatarUrl: httpsUrl.nullable().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, { message: 'Provide at least one field' });

const updateRole = z.strictObject({ role: selectableRole });

const deactivate = z.strictObject({ password: z.string().min(1).max(200) });

module.exports = { updateProfile, updateRole, deactivate };
