const { z } = require('zod');
const { phone } = require('../auth/auth.schemas');
const { ACCOUNT_STATUS, DOCUMENT_TYPES, VERIFICATION_STATUS } = require('./driver.constants');

function isRealDate(value) {
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function isAtLeast18(dateOfBirth) {
  const cutoff = new Date();
  cutoff.setUTCFullYear(cutoff.getUTCFullYear() - 18);
  return dateOfBirth <= cutoff.toISOString().slice(0, 10);
}

const isoDate = z.string().refine(isRealDate, 'Must be a date in YYYY-MM-DD format');

const licenceNumber = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z0-9-]{5,20}$/, 'Must be 5 to 20 letters, digits or hyphens');

const licenceExpiry = isoDate.refine(
  (value) => value >= new Date().toISOString().slice(0, 10),
  'The licence has expired',
);

// Sri Lankan NIC: old format is 9 digits and V or X, new format is 12 digits.
const nic = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^(\d{9}[VX]|\d{12})$/, 'Enter a valid Sri Lankan NIC number');

const dateOfBirth = isoDate.refine(isAtLeast18, 'Drivers must be at least 18 years old');

const contactDetails = {
  address: z.string().trim().min(1).max(500).optional(),
  emergencyContactName: z.string().trim().min(2).max(120).optional(),
  emergencyContactPhone: phone.optional(),
};

const bankAccount = z.strictObject({
  bank: z.string().trim().min(1).max(100),
  branch: z.string().trim().min(1).max(100),
  accountNumber: z.string().trim().regex(/^\d{5,20}$/, 'Must be 5 to 20 digits'),
  accountName: z.string().trim().min(1).max(100),
});

const paging = {
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
};

const register = z.strictObject({
  licenceNumber,
  licenceExpiry,
  nic,
  dateOfBirth: dateOfBirth.optional(),
  ...contactDetails,
});

const update = z
  .strictObject({
    licenceNumber: licenceNumber.optional(),
    licenceExpiry: licenceExpiry.optional(),
    bankAccount: bankAccount.optional(),
    ...contactDetails,
  })
  .refine((body) => Object.keys(body).length > 0, { message: 'Provide at least one field' });

const documentBody = z.strictObject({ type: z.enum(DOCUMENT_TYPES) });

const driverIdParams = z.strictObject({ id: z.uuid() });

const tripQuery = z.strictObject({
  status: z.enum(['SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']).optional(),
  ...paging,
});

const earningsQuery = z
  .strictObject({ from: isoDate.optional(), to: isoDate.optional() })
  .refine((query) => !query.from || !query.to || query.from <= query.to, {
    path: ['to'],
    message: 'Must not be before from',
  });

const queueQuery = z.strictObject({
  status: z.enum(Object.values(VERIFICATION_STATUS)).optional(),
  type: z.enum(['DRIVER', 'VEHICLE']).optional(),
  ...paging,
});

const verificationIdParams = z.strictObject({ id: z.uuid() });

const decision = z
  .strictObject({
    decision: z.enum([VERIFICATION_STATUS.APPROVED, VERIFICATION_STATUS.REJECTED]),
    reason: z.string().trim().min(1).max(500).optional(),
  })
  .refine((body) => body.decision !== VERIFICATION_STATUS.REJECTED || Boolean(body.reason), {
    path: ['reason'],
    message: 'A reason is required when rejecting',
  });

const accountStatus = z
  .strictObject({
    status: z.enum(Object.values(ACCOUNT_STATUS)),
    reason: z.string().trim().min(1).max(500).optional(),
  })
  .refine((body) => body.status === ACCOUNT_STATUS.ACTIVE || Boolean(body.reason), {
    path: ['reason'],
    message: 'A reason is required unless activating',
  });

module.exports = {
  register,
  update,
  documentBody,
  driverIdParams,
  tripQuery,
  earningsQuery,
  queueQuery,
  verificationIdParams,
  decision,
  accountStatus,
};
