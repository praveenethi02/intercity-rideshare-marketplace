// SCRUM-231: admins monitor passenger bookings. Read-only: admins cannot book or cancel here.
const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const validate = require('../../middleware/validate');
const respond = require('../../utils/respond');
const { ROLES } = require('../users/user.constants');
const schemas = require('./booking.schemas');
const bookingService = require('./booking.service');

const router = Router();

const pageMeta = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });

router.use(authenticate, requireRole(ROLES.ADMIN));

router.get('/', validate({ query: schemas.adminListQuery }), async (req, res) => {
  const query = req.validated.query;
  const { bookings, total } = await bookingService.adminListBookings(query);
  return respond(res, { message: 'Bookings loaded', data: { bookings }, meta: pageMeta(query, total) });
});

router.get('/:id', validate({ params: schemas.bookingIdParams }), async (req, res) => {
  const booking = await bookingService.adminGetBooking(req.user, req.validated.params.id);
  return respond(res, { message: 'Booking loaded', data: { booking } });
});

module.exports = router;