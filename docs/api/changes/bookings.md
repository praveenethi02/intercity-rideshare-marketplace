# Seat Booking API changes (Member 5, SCRUM-78)

For the PM to merge into `docs/api/openapi.yaml`. The full spec for these endpoints is in
[`docs/api/bookings.openapi.yaml`](../bookings.openapi.yaml). All paths start with `/api/v1` and need a
Bearer token. Responses use the standard `{ success, message, data, meta }` format, and errors put
their code in `meta.code` (validation errors also list `meta.details[]`). Money is LKR cents.

This first step covers **fixed-price** seat bookings only. Auction bids, payments, notifications
and cancelling bookings when the driver cancels the whole trip come in later steps.

## Endpoints

| Method | Path | Access | `data` |
| --- | --- | --- | --- |
| POST | `/bookings` | Bearer (not the trip's driver) | `booking` (201, status `CONFIRMED`) |
| GET | `/bookings/mine` | Bearer | `bookings`, with paging in `meta` |
| GET | `/bookings/:id` | The passenger, the trip's driver or an admin | `booking` |
| POST | `/bookings/:id/cancel` | The passenger | `booking` (status `CANCELLED`) |

Anyone signed in can book, whatever their role: a driver can book a seat on another driver's trip,
but not on their own. Users who may not see a booking get **404** `BOOKING_NOT_FOUND`, not 403, so
booking ids of other people are not revealed.

## Booking object

```json
{
  "id": "6f1c2a7e-0d3b-4c41-9a51-2f7d8e9b1c11",
  "reference": "BK-7Q2K9M",
  "status": "CONFIRMED",
  "tripId": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
  "passengerId": "c9b8a7d6-2222-4e3f-9a0b-1c2d3e4f5a6b",
  "fromStop": 1,
  "toStop": 3,
  "seats": 2,
  "pricePerSeatCents": 220000,
  "totalCents": 440000,
  "cancelReason": null,
  "createdAt": "2026-11-17T08:30:00.000Z",
  "cancelledAt": null,
  "pickup": { "stopOrder": 1, "name": "Kadawatha", "plannedAt": null },
  "drop": { "stopOrder": 3, "name": "Kandy", "plannedAt": null },
  "trip": {
    "id": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
    "driverId": "d1e2f3a4-3333-4b5c-8d6e-7f8a9b0c1d2e",
    "pricingMode": "FIXED",
    "status": "SCHEDULED",
    "originName": "Colombo Fort",
    "destinationName": "Kandy",
    "departureAt": "2026-11-18T01:30:00.000Z",
    "estimatedArrivalAt": null
  }
}
```

- `reference`: `BK-` and 6 characters from `A–Z` and `2–9`, without `0`, `O`, `1` or `I`. Unique.
  Show it to the passenger and driver.
- `fromStop` / `toStop`: stop order numbers on the trip (0 = first stop), the same numbers as
  `stops[].order` in `GET /trips/:id` and `pickup.stopOrder` / `drop.stopOrder` in `GET /trips/search`.
- `pricePerSeatCents` is the trip's price for that part of the route **when the booking was made**.
  It does not change if the driver changes the trip's price later. `totalCents = seats × pricePerSeatCents`.
- `status`: `CONFIRMED` or `CANCELLED`. `trip.status` is the trip's current status (`SCHEDULED`,
  `IN_PROGRESS`, `COMPLETED` or `CANCELLED`).
- `pickup.plannedAt` / `drop.plannedAt` are the driver's planned times for those stops, or `null`.

## POST `/bookings`

Books seats on a published FIXED-price trip, for the whole route or part of it.

Request:

```json
{ "tripId": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f", "fromStop": 1, "toStop": 3, "seats": 2 }
```

| Field | Rule |
| --- | --- |
| `tripId` | UUID of the trip |
| `fromStop` | Pickup stop order, integer ≥ 0 |
| `toStop` | Drop stop order, after `fromStop` and on the trip |
| `seats` | Integer 1–14 |

Do **not** send a price: the server takes it from the trip (the same `segmentPriceCents` that
`GET /trips/:id/availability` returns). Any field other than these four returns 422 `VALIDATION_ERROR`.

Response **201**:

```json
{
  "success": true,
  "message": "Booking confirmed",
  "data": { "booking": { "...": "Booking object, status CONFIRMED" } },
  "meta": null
}
```

The seats are held on that part of the route right away, in the same database transaction as the
booking, so a booking is never saved without its seats, or the other way round.

Checks, in this order:

| Status | `meta.code` | When |
| --- | --- | --- |
| 422 | `VALIDATION_ERROR` | Body fields missing, wrong type, out of range, or extra fields such as a price |
| 404 | `TRIP_NOT_FOUND` | No such trip, or the trip is still a `DRAFT` |
| 409 | `AUCTION_TRIP` | The trip sells seats by auction (bidding comes in a later sprint) |
| 403 | `OWN_TRIP` | The signed-in user is the trip's driver |
| 409 | `TRIP_NOT_BOOKABLE` | The trip is not `SCHEDULED` (it started, finished or was cancelled) |
| 409 | `TRIP_DEPARTED` | The trip is still `SCHEDULED` but its departure time has passed |
| 409 | `ALREADY_BOOKED` | The user already has a `CONFIRMED` booking on this trip. Cancel it to book again |
| 422 | `INVALID_SEGMENT` | `toStop` is not after `fromStop`, or a stop is not on this trip |
| 409 | `NOT_ENOUGH_SEATS` | Not enough free seats on that part of the route. `meta.details.seatsAvailable` says how many are left |
| 409 | `PRICE_CHANGED` | The driver changed the trip's price while the booking was being made. Load the price again and retry |

Example `NOT_ENOUGH_SEATS`:

```json
{
  "success": false,
  "message": "Not enough seats on this part of the route",
  "data": null,
  "meta": { "code": "NOT_ENOUGH_SEATS", "details": { "seatsAvailable": 1 } }
}
```

## GET `/bookings/mine`

The signed-in user's own bookings as a passenger, newest booking first.

Query (all optional):

| Param | Rule |
| --- | --- |
| `when` | `upcoming`: `CONFIRMED` bookings on trips that are `SCHEDULED` or `IN_PROGRESS`. `past`: everything else (completed or cancelled trips, and cancelled bookings). Leave out for all |
| `page` | Integer ≥ 1, default 1 |
| `limit` | 1–50, default 20 |

Response **200**:

```json
{
  "success": true,
  "message": "Bookings loaded",
  "data": { "bookings": [{ "...": "Booking object" }] },
  "meta": { "page": 1, "limit": 20, "total": 3, "totalPages": 1 }
}
```

Errors: 422 `VALIDATION_ERROR` for a bad `when`, `page` or `limit`.

## GET `/bookings/:id`

Response **200**: `{ "message": "Booking loaded", "data": { "booking": { ... } } }`

| Status | `meta.code` | When |
| --- | --- | --- |
| 422 | `VALIDATION_ERROR` | `id` is not a UUID |
| 404 | `BOOKING_NOT_FOUND` | No such booking, or the user is not its passenger, the trip's driver or an admin |

## POST `/bookings/:id/cancel`

Cancels the passenger's booking and gives the seats back to the trip, in one transaction.

Request (the body may be empty):

```json
{ "reason": "Plans changed" }
```

`reason` is optional, 3–300 characters.

Response **200**: `{ "message": "Booking cancelled", "data": { "booking": { "status": "CANCELLED", "cancelReason": "Plans changed", "cancelledAt": "…", ... } } }`

| Status | `meta.code` | When |
| --- | --- | --- |
| 422 | `VALIDATION_ERROR` | `id` is not a UUID, or `reason` is too short or too long |
| 404 | `BOOKING_NOT_FOUND` | No such booking, or the user is not its passenger (drivers and admins cannot cancel it here) |
| 409 | `ALREADY_CANCELLED` | The booking is already cancelled |
| 409 | `TRIP_NOT_CANCELLABLE` | The trip is no longer `SCHEDULED` (it started, finished or was cancelled). The booking and seats stay as they were |

## Errors on every endpoint

| Status | `meta.code` | When |
| --- | --- | --- |
| 401 | `UNAUTHORIZED` | Missing, invalid or signed-out token |
| 403 | `ACCOUNT_NOT_ACTIVE` | The account is deactivated or suspended |
| 429 | `TOO_MANY_REQUESTS` | Rate limit (same limiter as the trips endpoints) |

## Rules

- FIXED-price trips only. AUCTION trips return 409 `AUCTION_TRIP` until bidding is built.
- One `CONFIRMED` booking per passenger per trip. A cancelled booking does not count, so the
  passenger can book again after cancelling. The database enforces this with a unique index too,
  so two requests at the same time cannot both succeed.
- Seats are counted per route segment by the trips module. Booking Colombo → Kadawatha does not
  use a seat on Kadawatha → Kandy. See "Seats per route segment" in [`trips.md`](trips.md).
- Only the passenger can cancel, and only while the trip is `SCHEDULED`.

## For other modules

- **Ratings (Supasan):** a passenger rates a trip they had a `CONFIRMED` booking on whose
  `trip.status` is `COMPLETED`. `bookings.passenger_user_id` and `bookings.trip_id` link them.
  `require('../bookings')` exports `getBooking(id, viewer)` and `BOOKING_STATUS`.
- **Trip cancelled by the driver (later step):** `onTripCancelled` in `trips/trip.integrations.js`
  will cancel the trip's `CONFIRMED` bookings. Until then, those bookings stay `CONFIRMED` with
  `trip.status = CANCELLED`, and `GET /bookings/mine?when=past` lists them.

## Database

Migration `501_create_booking_tables.sql` adds `bookings`:

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Primary key |
| `reference` | TEXT | Unique, `BK-XXXXXX` |
| `trip_id` | UUID | → `trips.id` |
| `passenger_user_id` | UUID | → `users.id` |
| `from_stop`, `to_stop` | INTEGER | `from_stop ≥ 0`, `to_stop > from_stop` |
| `seats` | INTEGER | 1–14 |
| `price_per_seat_cents` | INTEGER | ≥ 0, saved at booking time |
| `total_cents` | INTEGER | `= seats × price_per_seat_cents` (CHECK) |
| `status` | TEXT | `CONFIRMED` or `CANCELLED` |
| `cancel_reason` | TEXT | Optional |
| `created_at`, `updated_at`, `cancelled_at` | TIMESTAMPTZ | `cancelled_at` is set exactly when `status = CANCELLED` (CHECK) |

Indexes: a unique partial index on `(trip_id, passenger_user_id) WHERE status = 'CONFIRMED'`,
`(passenger_user_id, created_at DESC)` for "my bookings" and `(trip_id, status)` for "bookings on a trip".
