-- Trip & Route Management (Member 4).
-- Column names on trips match what the driver module (201) already reads:
-- driver_user_id, origin_name, destination_name, departure_at, estimated_arrival_at,
-- pricing_mode, base_price_cents, seats_offered, seats_available, distance_m, duration_s,
-- status, cancel_reason, started_at, completed_at, cancelled_at.
-- vehicle_id gets its foreign key in a later migration, once the vehicles table exists.

CREATE TABLE trips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id UUID NOT NULL REFERENCES users (id),
  vehicle_id UUID NOT NULL,
  pricing_mode TEXT NOT NULL CHECK (pricing_mode IN ('AUCTION', 'FIXED')),
  status TEXT NOT NULL DEFAULT 'DRAFT'
    CHECK (status IN ('DRAFT', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
  origin_name TEXT NOT NULL,
  destination_name TEXT NOT NULL,
  departure_at TIMESTAMPTZ NOT NULL,
  estimated_arrival_at TIMESTAMPTZ,
  seats_offered INTEGER NOT NULL CHECK (seats_offered BETWEEN 1 AND 14),
  -- Seats still free for the whole route (origin to destination). Kept in step with trip_legs.
  seats_available INTEGER NOT NULL CHECK (seats_available >= 0),
  -- Full-route price in LKR cents. FIXED: seat price. AUCTION: starting bid.
  base_price_cents INTEGER NOT NULL CHECK (base_price_cents >= 0),
  distance_m INTEGER NOT NULL CHECK (distance_m > 0),
  duration_s INTEGER CHECK (duration_s IS NULL OR duration_s > 0),
  allows_cargo BOOLEAN NOT NULL DEFAULT FALSE,
  cargo_capacity_kg NUMERIC(8, 2),
  notes TEXT,
  cancel_reason TEXT,
  published_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (estimated_arrival_at IS NULL OR estimated_arrival_at > departure_at),
  CHECK (seats_available <= seats_offered),
  CHECK (NOT allows_cargo OR cargo_capacity_kg > 0)
);

CREATE INDEX trips_status_departure_idx ON trips (status, departure_at);
CREATE INDEX trips_driver_departure_idx ON trips (driver_user_id, departure_at DESC);

-- Ordered stops. stop_order 0 is the origin and the highest is the destination.
CREATE TABLE trip_stops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  stop_order INTEGER NOT NULL CHECK (stop_order >= 0),
  name TEXT NOT NULL,
  lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION NOT NULL CHECK (lng BETWEEN -180 AND 180),
  distance_from_start_m INTEGER NOT NULL DEFAULT 0 CHECK (distance_from_start_m >= 0),
  planned_at TIMESTAMPTZ,
  UNIQUE (trip_id, stop_order)
);

CREATE INDEX trip_stops_lat_lng_idx ON trip_stops (lat, lng);

-- One row per leg: leg i joins stop i and stop i + 1. A passenger from stop a to stop b
-- uses legs a to b - 1, so seats are held per route segment.
CREATE TABLE trip_legs (
  trip_id UUID NOT NULL REFERENCES trips (id) ON DELETE CASCADE,
  leg_index INTEGER NOT NULL CHECK (leg_index >= 0),
  seats_reserved INTEGER NOT NULL DEFAULT 0 CHECK (seats_reserved >= 0),
  PRIMARY KEY (trip_id, leg_index)
);

-- A driver's reusable route templates.
CREATE TABLE saved_routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  stops JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (driver_user_id, name)
);
