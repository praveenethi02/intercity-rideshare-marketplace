# Trip & Route Management API changes (Member 4)

For the PM to merge into `docs/api/openapi.yaml`. The full spec for these endpoints is in
[`docs/api/trips.openapi.yaml`](../trips.openapi.yaml). All paths start with `/api/v1` and need a
Bearer token. Responses use the standard `{ success, message, data, meta }` format, and errors put
their code in `meta.code`. Money is LKR cents.

## Endpoints

| Method | Path | Access | `data` |
| --- | --- | --- | --- |
| POST | `/trips` | Driver | `trip` (201, status `DRAFT`) |
| GET | `/trips/mine` | Driver | `trips`, with paging in `meta` |
| GET | `/trips/search` | Bearer | `results`, with paging and `radiusKm` in `meta` |
| GET | `/trips/:id` | Bearer (drafts: owner or admin) | `trip` with `stops` and `legs` |
| PATCH | `/trips/:id` | Owner or admin | `trip` |
| GET | `/trips/:id/availability` | Bearer | `availability` |
| POST | `/trips/:id/publish` | Owner or admin | `trip` |
| POST | `/trips/:id/start` | Owner | `trip` |
| POST | `/trips/:id/complete` | Owner | `trip` |
| POST | `/trips/:id/cancel` | Owner or admin | `trip` |
| GET | `/saved-routes` | Driver | `savedRoutes` |
| POST | `/saved-routes` | Driver | `savedRoute` (201) |
| DELETE | `/saved-routes/:id` | Driver | `null` |

## Requests

**POST `/trips`**: requires `vehicleId`, `pricingMode` (`FIXED` or `AUCTION`), `departureAt`,
`seatsOffered` (1–14), `basePriceCents` (full-route seat price, or starting bid for auctions) and
`stops` (2–15 of `{ name, lat, lng, plannedAt? }`, in driving order). Optional: `estimatedArrivalAt`,
`allowsCargo`, `cargoCapacityKg` (required when `allowsCargo` is true) and `notes`.

**PATCH `/trips/:id`**: any of the fields above except `vehicleId` and `pricingMode`.
- `DRAFT`: every field can change.
- `SCHEDULED` with no seats reserved: `estimatedArrivalAt`, `basePriceCents`, `seatsOffered` and `notes`.
- `SCHEDULED` with seats reserved: `estimatedArrivalAt` and `notes`.
- Anything else returns 409 `TRIP_LOCKED`, with the editable fields in `meta.details.editable`.

**GET `/trips/search`**: `fromLat`, `fromLng`, `toLat`, `toLng`, `date` (`YYYY-MM-DD`, Sri Lankan
day), optional `seats` (default 1), `radiusKm` (default 5), `pricingMode`, `page`, `limit`.
It finds published trips that have a stop near the pickup point and a *later* stop near the drop
point, with enough free seats on that part of the route.

**GET `/trips/:id/availability`**: `fromStop` and `toStop` (stop order numbers).

**POST `/trips/:id/cancel`**: `{ reason }` (3–300 characters).

**POST `/saved-routes`**: `{ name, stops }`. Names are unique per driver.

## Rules

- Departure must be 30 minutes to 60 days ahead. Arrival must be after departure.
- Consecutive stops must be at least 200 m apart.
- Distance is the straight line × 1.25. Replace it with Google Directions later.
- A segment's price is proportional to its distance, rounded to LKR 10.
- Lifecycle: `DRAFT → SCHEDULED → IN_PROGRESS → COMPLETED`, and `DRAFT/SCHEDULED → CANCELLED`.
  `POST /trips/:id/publish` moves a draft to `SCHEDULED`. These are the statuses in the drivers
  module's contract, plus `DRAFT` for trips the driver has not published yet. `GET /drivers/me/trips`
  lists drafts too, but its `status` filter does not accept `DRAFT` yet.
  A driver can start at most 30 minutes before departure.
- When `driver_profiles` exists (drivers module), only `APPROVED` and `ACTIVE` drivers can create
  trips (403 `DRIVER_NOT_VERIFIED`).
- The vehicle must be the driver's own (403 `VEHICLE_NOT_OWNED`), `APPROVED` (403
  `VEHICLE_NOT_APPROVED`) and active (403 `VEHICLE_INACTIVE`), the same rule as
  `getUsableVehicle` in the vehicles module. `seatsOffered` can be at most the vehicle's
  `passengerSeats` (422 `TOO_MANY_SEATS`). `passengerSeats` already leaves out the driver's seat.
  The seat limit is checked again when `seatsOffered` is edited.

## Seats per route segment (for the Booking and Auction modules)

Stops `0..n-1` make legs `0..n-2`. A passenger from stop `a` to stop `b` uses legs `a..b-1`. Free
seats on a segment = `seatsOffered − (busiest leg in it)`. So Colombo → Kadawatha and Kadawatha →
Kandy can sell the same seat. `trips.seats_available` is the free count for the whole route.

Call these inside the transaction that saves your booking:

```js
const db = require('../../db');
const { reserveSeats, releaseSeats } = require('../trips');

await db.transaction(async (tx) => {
  await reserveSeats(tx, tripId, pickupStop, dropStop, seats); // 409 NOT_ENOUGH_SEATS if full
  // ...insert the booking with the same tx
});

// Cancelled booking, refund or unpaid auction win:
await db.transaction((tx) => releaseSeats(tx, tripId, pickupStop, dropStop, seats));
```

## Database

Migration `401_create_trip_tables.sql` adds `trips`, `trip_stops`, `trip_legs` and `saved_routes`.
The `trips` columns match what the drivers module already reads for `GET /drivers/me/trips` and
completed-trip counts (`driver_user_id`, `departure_at`, `origin_name`, `seats_available`,
`distance_m`, …). `vehicle_id` gets its foreign key in a later migration, once `vehicles` exists.
