# Ratings and Reviews API changes (Member 2, SCRUM-125 to SCRUM-134)

For the PM to merge into `docs/api/openapi.yaml`. All paths start with `/api/v1` and need a Bearer
token. Responses use the standard `{ success, message, data, meta }` format, and errors put their
code in `meta.code` (validation errors also list `meta.details[]`).

After a trip is `COMPLETED`, each passenger who had a `CONFIRMED` booking on it can rate the
driver, and the driver can rate each of those passengers. Cargo ratings (SCRUM-127, 128),
notifications, and editing or deleting a rating are not part of this step.

## Endpoints

| Method | Path | Access | `data` |
| --- | --- | --- | --- |
| POST | `/ratings` | Bearer (the trip's driver or a passenger on it) | `rating` (201) |
| GET | `/ratings/pending` | Bearer | `pending` |
| GET | `/ratings/users/:userId` | Bearer | `averageRating`, `ratingCount`, `ratings`, with paging in `meta` |
| GET | `/ratings/mine` | Bearer | `ratings`, with paging in `meta` |

## Who can rate whom

| The signed-in user is… | They can rate… | `raterRole` saved |
| --- | --- | --- |
| A passenger with a `CONFIRMED` booking on the trip | The trip's driver | `PASSENGER` |
| The trip's driver | Each passenger with a `CONFIRMED` booking on the trip | `DRIVER` |

- Only after the trip's `status` is `COMPLETED`.
- Nobody can rate themselves, and passengers cannot rate each other.
- A cancelled booking does not count.
- One rating per rater, per person rated, per trip. A second one returns 409 `ALREADY_RATED`.
- The server works out `raterRole` from the trip. The app never sends it.

## Rating object

```json
{
  "id": "0b6f2c1e-4a5d-4e7f-9a8b-1c2d3e4f5a6b",
  "tripId": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
  "raterId": "c9b8a7d6-2222-4e3f-9a0b-1c2d3e4f5a6b",
  "rateeId": "d1e2f3a4-3333-4b5c-8d6e-7f8a9b0c1d2e",
  "raterRole": "PASSENGER",
  "stars": 5,
  "review": "Safe driving and on time.",
  "createdAt": "2026-11-21T14:05:00.000Z"
}
```

- `stars`: whole number 1–5.
- `review`: the trimmed text, or `null` when there is none.
- `raterRole`: `PASSENGER` when a passenger rated the driver, `DRIVER` when the driver rated a passenger.

The list endpoints add the other person and the trip to each rating:

```json
"reviewer": { "id": "c9b8a7d6-2222-4e3f-9a0b-1c2d3e4f5a6b", "name": "Nimal S." },
"trip": {
  "id": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
  "originName": "Colombo Fort",
  "destinationName": "Kandy",
  "departureAt": "2026-11-20T01:30:00.000Z",
  "completedAt": "2026-11-20T05:10:00.000Z"
}
```

Names are shortened to the first name and the last initial ("Nimal Silva" becomes "Nimal S."),
the same as public driver profiles. A one-word name is shown as it is.

## POST `/ratings`

Request:

```json
{
  "tripId": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
  "rateeId": "d1e2f3a4-3333-4b5c-8d6e-7f8a9b0c1d2e",
  "stars": 5,
  "review": "Safe driving and on time."
}
```

| Field | Rule |
| --- | --- |
| `tripId` | UUID of a `COMPLETED` trip the signed-in user drove or had a `CONFIRMED` booking on |
| `rateeId` | UUID of the person being rated: the driver, or one of the trip's passengers |
| `stars` | Integer 1–5 |
| `review` | Optional string, at most 500 characters after trimming. `null`, a missing field and a blank string are all saved as `null` |

Any other field returns 422 `VALIDATION_ERROR`.

Response **201**:

```json
{
  "success": true,
  "message": "Rating saved",
  "data": { "rating": { "...": "Rating object" } },
  "meta": null
}
```

When a passenger rates the driver, the driver's `averageRating` and `ratingCount` on
`GET /drivers/:id` and `GET /drivers/me` update in the same database transaction as the rating.

Checks, in this order:

| Status | `meta.code` | When |
| --- | --- | --- |
| 422 | `VALIDATION_ERROR` | Fields missing, wrong type, `stars` not a whole number 1–5, `review` over 500 characters, or extra fields |
| 422 | `CANNOT_RATE_SELF` | `rateeId` is the signed-in user |
| 404 | `TRIP_NOT_FOUND` | No such trip, or the signed-in user was neither its driver nor a passenger with a `CONFIRMED` booking. Not 403, so other people's trip ids are not revealed |
| 409 | `TRIP_NOT_COMPLETED` | The trip is not `COMPLETED` yet (or was cancelled) |
| 422 | `RATEE_NOT_ON_TRIP` | The driver chose someone without a `CONFIRMED` booking on the trip, or a passenger chose someone other than the driver |
| 409 | `ALREADY_RATED` | The signed-in user already rated this person for this trip |

Example `VALIDATION_ERROR`:

```json
{
  "success": false,
  "message": "Request validation failed",
  "data": null,
  "meta": {
    "code": "VALIDATION_ERROR",
    "details": [{ "field": "body.stars", "message": "Too big: expected number to be <=5" }]
  }
}
```

## GET `/ratings/pending`

Everyone the signed-in user can still rate on `COMPLETED` trips, most recently completed trip
first. Use it for a "Rate your trip" list. An item disappears once that rating is saved. This list
has no paging.

Response **200**:

```json
{
  "success": true,
  "message": "Pending ratings loaded",
  "data": {
    "pending": [
      {
        "trip": {
          "id": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
          "originName": "Colombo Fort",
          "destinationName": "Kandy",
          "departureAt": "2026-11-20T01:30:00.000Z",
          "completedAt": "2026-11-20T05:10:00.000Z"
        },
        "ratee": { "id": "d1e2f3a4-3333-4b5c-8d6e-7f8a9b0c1d2e", "name": "Kamal P.", "role": "DRIVER" }
      }
    ]
  },
  "meta": null
}
```

- `ratee.role` is that person's part in the trip: `DRIVER` for a passenger's list, `PASSENGER` for
  the driver's list. A user who both drove and travelled can see both kinds.
- Send `trip.id` as `tripId` and `ratee.id` as `rateeId` to `POST /ratings`.

## GET `/ratings/users/:userId`

The ratings a user received, newest first, with their average. Any signed-in user can read them,
for example on a driver's profile before booking.

Query (all optional):

| Param | Rule |
| --- | --- |
| `role` | `DRIVER`: only ratings the user received as a driver (from passengers). `PASSENGER`: only ratings they received as a passenger (from drivers). Leave out for all |
| `page` | Integer ≥ 1, default 1 |
| `limit` | 1–50, default 20 |

Response **200**:

```json
{
  "success": true,
  "message": "Ratings loaded",
  "data": {
    "averageRating": 4.67,
    "ratingCount": 3,
    "ratings": [
      {
        "id": "0b6f2c1e-4a5d-4e7f-9a8b-1c2d3e4f5a6b",
        "tripId": "a3d4e5f6-1111-4c2d-8e9f-0a1b2c3d4e5f",
        "raterId": "c9b8a7d6-2222-4e3f-9a0b-1c2d3e4f5a6b",
        "rateeId": "d1e2f3a4-3333-4b5c-8d6e-7f8a9b0c1d2e",
        "raterRole": "PASSENGER",
        "stars": 5,
        "review": "Safe driving and on time.",
        "createdAt": "2026-11-21T14:05:00.000Z",
        "reviewer": { "id": "c9b8a7d6-2222-4e3f-9a0b-1c2d3e4f5a6b", "name": "Nimal S." },
        "trip": { "...": "trip summary, as above" }
      }
    ]
  },
  "meta": { "page": 1, "limit": 20, "total": 3, "totalPages": 1 }
}
```

- `averageRating` is worked out from every rating that matches `role` (not just this page),
  rounded to 2 decimals. It is `null` when there are no ratings, so show "No ratings yet" rather
  than 0.
- `ratingCount` and `meta.total` are the same number.
- For a driver, `averageRating` with `role=DRIVER` matches `averageRating` on `GET /drivers/:id`,
  apart from rounding.

| Status | `meta.code` | When |
| --- | --- | --- |
| 422 | `VALIDATION_ERROR` | `userId` is not a UUID, or a bad `role`, `page` or `limit` |
| 404 | `USER_NOT_FOUND` | No user with that id |

## GET `/ratings/mine`

The ratings the signed-in user gave, newest first. Each one has `ratee` (`{ id, name }`) and `trip`
instead of `reviewer`.

Query: `page` (≥ 1, default 1) and `limit` (1–50, default 20).

Response **200**: `{ "message": "Ratings loaded", "data": { "ratings": [ ... ] }, "meta": { "page": 1, "limit": 20, "total": 2, "totalPages": 1 } }`

Errors: 422 `VALIDATION_ERROR` for a bad `page` or `limit`.

## Errors on every endpoint

| Status | `meta.code` | When |
| --- | --- | --- |
| 401 | `UNAUTHORIZED` | Missing, invalid or signed-out token |
| 403 | `ACCOUNT_NOT_ACTIVE` | The account is deactivated or suspended |
| 429 | `TOO_MANY_REQUESTS` | Rate limit (the same limiter as trips and bookings) |

## For other modules

- **Drivers:** the ratings module calls `driverRepository.addRating(driverUserId, stars, tx)` inside
  its transaction, so `driver_profiles.rating_avg` and `rating_count` stay in step with the ratings
  table. The drivers module itself did not change.
- **Passengers:** there are no rating columns on users. A passenger's average comes from
  `GET /ratings/users/:userId?role=PASSENGER`.

## Database

Migration `601_create_rating_tables.sql` adds `ratings`:

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Primary key |
| `trip_id` | UUID | → `trips.id` |
| `rater_user_id` | UUID | → `users.id`, the person who rated |
| `ratee_user_id` | UUID | → `users.id`, the person rated. Not the same as `rater_user_id` (CHECK) |
| `rater_role` | TEXT | `DRIVER` or `PASSENGER` |
| `stars` | INTEGER | 1–5 (CHECK) |
| `review` | TEXT | Optional, 1–500 characters when present (CHECK) |
| `created_at` | TIMESTAMPTZ | Default `now()` |

Indexes: a unique index on `(trip_id, rater_user_id, ratee_user_id)` for one rating per trip, which
also serves "ratings on a trip", `(ratee_user_id, created_at DESC)` for "ratings I received" and
`(rater_user_id, created_at DESC)` for "ratings I gave".
