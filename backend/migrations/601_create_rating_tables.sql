-- Ratings and Reviews (Member 2, SCRUM-125 to SCRUM-134). After a COMPLETED trip, a passenger with a
-- CONFIRMED booking rates the trip's driver, and the driver rates each such passenger.
-- The service checks who may rate whom. The table only stops ratings no rule could allow.
-- Keep rater_role the same as RATER_ROLE in src/modules/ratings/rating.constants.js.

CREATE TABLE ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips (id),
  rater_user_id UUID NOT NULL REFERENCES users (id),
  ratee_user_id UUID NOT NULL REFERENCES users (id),
  -- The rater's part in the trip: DRIVER rates a passenger, PASSENGER rates the driver.
  rater_role TEXT NOT NULL CHECK (rater_role IN ('DRIVER', 'PASSENGER')),
  stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  -- Optional. The API trims it and saves an empty review as NULL.
  review TEXT CHECK (review IS NULL OR char_length(review) BETWEEN 1 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (rater_user_id <> ratee_user_id)
);

-- One rating per rater, per person rated, per trip. It starts with trip_id, so it also serves
-- "ratings on a trip".
CREATE UNIQUE INDEX ratings_one_per_trip_idx ON ratings (trip_id, rater_user_id, ratee_user_id);

-- "Ratings I received", newest first, and the average.
CREATE INDEX ratings_ratee_created_idx ON ratings (ratee_user_id, created_at DESC);

-- "Ratings I gave", newest first.
CREATE INDEX ratings_rater_created_idx ON ratings (rater_user_id, created_at DESC);
