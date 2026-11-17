const { z } = require('zod');
const { BOOKING_WHEN, BOOKING_RULES } = require('./booking.constants');

// Stop order is checked against the trip by the service (422 INVALID_SEGMENT), so a drop stop
// before the pickup gets the same error code here as from GET /trips/:id/availability.
const createBooking = z.strictObject({
  tripId: z.uuid(),
  fromStop: z.number().int().min(0),
  toStop: z.number().int().min(1),
  seats: z.number().int().min(1).max(BOOKING_RULES.MAX_SEATS),
});

const myBookingsQuery = z.strictObject({
  when: z.enum(Object.values(BOOKING_WHEN)).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

const bookingIdParams = z.strictObject({ id: z.uuid() });

const cancelBooking = z.strictObject({ reason: z.string().trim().min(3).max(300).optional() });

module.exports = { createBooking, myBookingsQuery, bookingIdParams, cancelBooking };
