// Seat and cargo limits per vehicle type are not checked here, because PATCH needs the merged
// (old + new) values. See typeLimitErrors in vehicleTypes.js, called from vehicle.service.js.
const { z } = require('zod');
const { normalizePlate, isValidPlate } = require('./plate');
const { VEHICLE_TYPE_KEYS } = require('./vehicleTypes');

const VERIFICATION_STATUSES = ['NOT_SUBMITTED', 'PENDING', 'APPROVED', 'REJECTED'];
const DOC_TYPES = [
  'REGISTRATION_CERT',
  'REVENUE_LICENSE',
  'INSURANCE',
  'PHOTO_FRONT',
  'PHOTO_BACK',
  'PHOTO_INTERIOR',
];
const REQUIRED_DOC_TYPES = ['REGISTRATION_CERT', 'REVENUE_LICENSE', 'INSURANCE', 'PHOTO_FRONT'];

const text = (max) => z.string().trim().min(1).max(max);
const count = z.number().int().min(0);

const plateNumber = z
  .string()
  .transform(normalizePlate)
  .refine(isValidPlate, { message: 'Invalid Sri Lankan plate number (e.g. WP CAB-1234, CAB-1234, 65-1234)' });

const year = z
  .number()
  .int()
  .min(1990)
  .refine((value) => value <= new Date().getFullYear() + 1, {
    message: 'year cannot be later than next year',
  });

const vehicleFields = {
  vehicleType: z.enum(VEHICLE_TYPE_KEYS),
  make: text(50),
  model: text(50),
  year,
  color: text(30),
  plateNumber,
  totalSeats: z.number().int().min(1).max(100),
};

const createVehicleBody = z.object({
  ...vehicleFields,
  passengerSeats: z.number().int().min(1).max(99).optional(), // Defaults to totalSeats - 1.
  cargoCapacityKg: count.default(0),
  cargoVolumeL: count.default(0),
});

const updateVehicleBody = z
  .object({
    ...vehicleFields,
    passengerSeats: z.number().int().min(1).max(99),
    cargoCapacityKg: count,
    cargoVolumeL: count,
  })
  .partial()
  .refine((body) => Object.keys(body).length > 0, { message: 'Send at least one field to update' });

const idParams = z.object({ id: z.uuid() });

const setActiveBody = z.object({ isActive: z.boolean() });

const uploadDocumentBody = z.object({ docType: z.enum(DOC_TYPES) });

const adminListQuery = z.object({
  verificationStatus: z.enum(VERIFICATION_STATUSES).optional(),
  type: z.enum(VEHICLE_TYPE_KEYS).optional(),
  q: z.string().trim().min(1).max(100).optional(),
  isActive: z.enum(['true', 'false']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const adminDecisionBody = z
  .object({
    decision: z.enum(['APPROVE', 'REJECT']),
    reason: z.string().trim().max(500).optional(),
    documents: z
      .array(z.object({ id: z.uuid(), status: z.enum(['ACCEPTED', 'REJECTED']) }))
      .optional(),
  })
  .refine((body) => body.decision !== 'REJECT' || (body.reason && body.reason.length >= 3), {
    message: 'reason is required when rejecting (min 3 characters)',
    path: ['reason'],
  });

const adminStatusBody = z
  .object({
    isActive: z.boolean(),
    reason: z.string().trim().max(500).optional(),
  })
  .refine((body) => body.isActive || (body.reason && body.reason.length >= 3), {
    message: 'reason is required when deactivating (min 3 characters)',
    path: ['reason'],
  });

module.exports = {
  VERIFICATION_STATUSES,
  DOC_TYPES,
  REQUIRED_DOC_TYPES,
  createVehicleBody,
  updateVehicleBody,
  idParams,
  setActiveBody,
  uploadDocumentBody,
  adminListQuery,
  adminDecisionBody,
  adminStatusBody,
};
