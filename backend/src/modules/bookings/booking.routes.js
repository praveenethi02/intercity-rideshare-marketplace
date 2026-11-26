const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const validate = require('../../middleware/validate');
const { apiRateLimit } = require('../../middleware/rate-limit');
const respond = require('../../utils/respond');
const schemas = require('./booking.schemas');
const bookingService = require('./booking.service');

const router = Router();
const byId = { params: schemas.bookingIdParams };

const pageMeta = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });

router.use(apiRateLimit, authenticate);

router.post('/', validate({ body: schemas.createBooking }), async (req, res) => {
  const booking = await bookingService.createBooking(req.user, req.validated.body);
  return respond(res, { status: 201, message: 'Booking confirmed', data: { booking } });
});

// Static path before /:id so it is not read as a booking id.
router.get('/mine', validate({ query: schemas.myBookingsQuery }), async (req, res) => {
  const query = req.validated.query;
  const { bookings, total } = await bookingService.listMyBookings(req.user, query);
  return respond(res, { message: 'Bookings loaded', data: { bookings }, meta: pageMeta(query, total) });
});

router.get('/:id', validate(byId), async (req, res) => {
  const booking = await bookingService.getBookingDetail(req.validated.params.id, req.user);
  return respond(res, { message: 'Booking loaded', data: { booking } });
});

router.post('/:id/cancel', validate({ ...byId, body: schemas.cancelBooking }), async (req, res) => {
  const booking = await bookingService.cancelBooking(req.user, req.validated.params.id, req.validated.body.reason);
  return respond(res, { message: 'Booking cancelled', data: { booking } });
});

module.exports = router;
