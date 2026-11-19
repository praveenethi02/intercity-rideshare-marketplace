-- Seat Booking (Member 5). Fixed-price seat bookings on part or all of a trip's route.
-- Seats are held on trip_legs by the trips module (reserveSeats / releaseSeats), in the same
-- transaction that inserts or cancels the booking.
-- Keep the status list the same as BOOKING_STATUS in src/modules/bookings/booking.constants.js.

CREATE TABLE bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Short code the passenger and driver can read out, e.g. BK-7Q2K9M.
  reference TEXT NOT NULL UNIQUE CHECK (reference ~ '^BK-[A-Z0-9]{6}$'),
  trip_id UUID NOT NULL REFERENCES trips (id),
  passenger_user_id UUID NOT NULL REFERENCES users (id),
  -- Stop order numbers on the trip (0 = first stop). The passenger uses legs from_stop..to_stop-1.
  from_stop INTEGER NOT NULL CHECK (from_stop >= 0),
  to_stop INTEGER NOT NULL,
  seats INTEGER NOT NULL CHECK (seats BETWEEN 1 AND 14),
  -- LKR cents, saved at booking time so later price changes do not affect this booking.
  price_per_seat_cents INTEGER NOT NULL CHECK (price_per_seat_cents >= 0),
  total_cents INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'CONFIRMED' CHECK (status IN ('CONFIRMED', 'CANCELLED')),
  cancel_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at TIMESTAMPTZ,
  CHECK (to_stop > from_stop),
  CHECK (total_cents = seats * price_per_seat_cents),
  CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL))
);

-- One CONFIRMED booking per passenger per trip. A cancelled booking does not block a new one.
CREATE UNIQUE INDEX bookings_one_confirmed_per_trip_idx
  ON bookings (trip_id, passenger_user_id) WHERE status = 'CONFIRMED';

-- "My bookings", newest first.
CREATE INDEX bookings_passenger_created_idx ON bookings (passenger_user_id, created_at DESC);

-- "Bookings on a trip" (driver's passenger list, and cancelling them when a trip is cancelled).
CREATE INDEX bookings_trip_status_idx ON bookings (trip_id, status);
