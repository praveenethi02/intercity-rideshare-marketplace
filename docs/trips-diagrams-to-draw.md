# Diagrams Member 4 must draw by hand (Draw.io)

The mentor asked that diagrams are **drawn by hand in Draw.io, not generated**.
This page lists what each diagram must contain. Draw them yourself, save the `.drawio`
file in `docs/diagrams/`, and embed them in Confluence with the Draw.io plugin.

## 1. Trip status (state diagram)
- States: DRAFT, SCHEDULED, IN_PROGRESS, COMPLETED, CANCELLED.
- Arrows and labels:
  - DRAFT → SCHEDULED: *publish*.
  - SCHEDULED → IN_PROGRESS: *start (≤ 30 min before departure)*.
  - IN_PROGRESS → COMPLETED: *complete*.
  - DRAFT → CANCELLED and SCHEDULED → CANCELLED: *cancel (reason required)*.
- Add a note on each state saying what can be edited (see `docs/api/changes/trips.md`, "Requests").
- Start dot → DRAFT. COMPLETED and CANCELLED → end dot.

## 2. Stops, legs and seats per segment
- Draw 4 stops in a line: Colombo Fort (0), Kadawatha (1), Kegalle (2), Kandy (3).
- Draw 3 legs between them: leg 0, leg 1, leg 2. Each leg has a box "seats_reserved".
- Show two passengers:
  - A: Colombo → Kadawatha, which uses leg 0 only.
  - B: Kadawatha → Kandy, which uses legs 1 and 2.
- Write the rule: free seats = seats_offered − max(seats_reserved on the legs used).
- Show that A and B can use the **same physical seat**.

## 3. Search sequence (Flutter → API → DB)
Lifelines: Passenger app, Express API, trip.service, PostgreSQL.
1. App: `GET /trips/search?fromLat…&date&seats`.
2. API: `authenticate`, `validate` (zod), then `searchTrips`.
3. Service: build two bounding boxes, then call `searchCandidates`. This is a SQL join of trips × stops × stops, keeping only pairs where the drop stop comes after the pickup stop.
4. Service: compute exact distances, keep the closest pair per trip, and load the legs.
5. Service: compute free seats and the segment price, filter by seats, then sort.
6. API → App: the `{ success, data: [...], meta }` envelope.

## 4. Create & publish trip (sequence)
Lifelines: Driver app, API, trip.service, integrations (vehicles), PostgreSQL.
1. Wizard → `POST /trips`, then `db.transaction` (BEGIN).
2. Driver check (driver_profiles APPROVED) and vehicle check (owner + APPROVED + seat capacity).
3. INSERT into trips, trip_stops and trip_legs, then COMMIT.
4. Return 201 (DRAFT).
5. `POST /trips/:id/publish` → SELECT … FOR UPDATE → status check → UPDATE → 200.

## 5. ERD part (add to the team ERD)
- `trips` (PK id; FK driver_user_id → users; vehicle_id → vehicles later), 1–N `trip_stops`, 1–N `trip_legs`.
- `saved_routes` (FK driver_user_id → users).
- Copy the columns from `backend/migrations/401_create_trip_tables.sql`.

## 6. Mobile screen flow
Driver:
- My trips (tabs) → New trip wizard (Route → Schedule → Seats & price → Review) → Trip detail.
- From Trip detail: Edit, Publish, Start → Active trip → Complete, or Cancel.
- Saved routes: list → new route form; "use saved route" from the wizard.

Passenger:
- Find a ride → Stop picker → Results (sort/filter) → Ride detail → Book/Bid. The Book/Bid step belongs to the Booking/Auction members.
