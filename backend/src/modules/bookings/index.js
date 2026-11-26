// What other modules may use from bookings.
const bookingRoutes = require('./booking.routes');
const bookingAdminRoutes = require('./booking.admin.routes');
const { getBooking } = require('./booking.service');
const { BOOKING_STATUS } = require('./booking.constants');

module.exports = { bookingRoutes, bookingAdminRoutes, getBooking, BOOKING_STATUS };