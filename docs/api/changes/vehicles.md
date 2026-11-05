# API changes — Vehicles module (Member 3, SCRUM-48 → SCRUM-56)

For the PM to merge into `docs/api/openapi.yaml`. All responses use the standard envelope
`{ success, message, data, meta }`; errors use `meta.code` (+ `meta.details[]` for validation).

## Vehicle object

```json
{
  "id": "uuid",
  "driverUserId": "uuid",
  "vehicleType": "CAR | SUV | VAN | MINIBUS | BUS | PICKUP | LORRY",
  "make": "Toyota",
  "model": "Axio",
  "year": 2016,
  "color": "White",
  "plateNumber": "WP CAB-1234",
  "totalSeats": 5,
  "passengerSeats": 4,
  "cargoCapacityKg": 50,
  "cargoVolumeL": 300,
  "verificationStatus": "NOT_SUBMITTED | PENDING | APPROVED | REJECTED",
  "rejectionReason": null,
  "verifiedAt": null,
  "verifiedBy": null,
  "isActive": true,
  "createdAt": "2026-11-04T05:00:00.000Z",
  "updatedAt": "2026-11-04T05:00:00.000Z"
}
```

## VehicleDocument object

```json
{ "id": "uuid", "vehicleId": "uuid", "docType": "REGISTRATION_CERT", "fileUrl": "http://localhost:4000/api/v1/files/<key>.pdf?expires=…&sig=…", "status": "UPLOADED | ACCEPTED | REJECTED", "uploadedAt": "…" }
```

`fileUrl` is a signed link that expires after 15 minutes. Fetch the document again for a new link.

`docType`: `REGISTRATION_CERT`, `REVENUE_LICENSE`, `INSURANCE`, `PHOTO_FRONT`, `PHOTO_BACK`, `PHOTO_INTERIOR`.
Required before submit: `REGISTRATION_CERT`, `REVENUE_LICENSE`, `INSURANCE`, `PHOTO_FRONT`.

## Rules

| Rule | Detail |
|---|---|
| Max vehicles | 3 per driver (4th → 409 `CONFLICT`) |
| Plate | normalised to upper case, single spaces, `-` before last 4 digits. Accepts `WP CAB-1234`, `CAB-1234`, `KX-1234`, `65-1234`, `250-1234`. Unique → 409 `CONFLICT` |
| Year | 1990 … current year + 1 |
| Seats | `totalSeats` includes driver, within type limits. `passengerSeats` default `totalSeats-1`, must be `1 ≤ passengerSeats < totalSeats` |
| Cargo | `cargoCapacityKg`, `cargoVolumeL` ≥ 0 and ≤ type limit (0 = no cargo) |
| Re-verification | Editing `plateNumber`, `vehicleType`, `totalSeats`, `passengerSeats`, `cargoCapacityKg`, `cargoVolumeL` on an APPROVED vehicle → `PENDING` (+ audit log). Uploading a document to an APPROVED vehicle → `PENDING`. `make/model/year/color` edits keep the status |
| Usable for trips | owner + `APPROVED` + `is_active = true` (`isVehicleUsable()` in `modules/vehicles/vehicle.service.js`) |

### Type limits (`GET /vehicles/types`)

| Type | Seats (incl. driver) | Max cargo kg | Max cargo L |
|---|---|---|---|
| CAR | 2–5 | 100 | 500 |
| SUV | 5–8 | 200 | 800 |
| VAN | 5–15 | 800 | 3000 |
| MINIBUS | 10–30 | 500 | 2000 |
| BUS | 20–60 | 1000 | 5000 |
| PICKUP | 2–5 | 1000 | 3000 |
| LORRY | 2–3 | 5000 | 20000 |

---

## Driver endpoints — `/api/v1/vehicles`

Auth: `Bearer` token. Role `DRIVER` unless noted. Non-owners get **404** (ids of other drivers' vehicles are not revealed).

### GET /api/v1/vehicles/types  (any logged-in user)
200 → `data: [{ type, label, minSeats, maxSeats, maxCargoKg, maxCargoVolumeL, allowsCargo }]`

### POST /api/v1/vehicles
Body:
```json
{ "vehicleType": "CAR", "make": "Toyota", "model": "Axio", "year": 2016, "color": "White",
  "plateNumber": "wp cab 1234", "totalSeats": 5, "passengerSeats": 4, "cargoCapacityKg": 50, "cargoVolumeL": 300 }
```
`passengerSeats`, `cargoCapacityKg`, `cargoVolumeL` optional.
201 → Vehicle (status `NOT_SUBMITTED`). Errors: 401, 403 (not DRIVER), 422 `VALIDATION_ERROR` (fields / type limits), 409 `CONFLICT` (plate taken, or already 3 vehicles).

### GET /api/v1/vehicles/mine
200 → `Vehicle[]` (oldest first).

### GET /api/v1/vehicles/:id  (owner or ADMIN)
200 → Vehicle. 404 `VEHICLE_NOT_FOUND` if not found / not owner. 422 if id is not a UUID.

### PATCH /api/v1/vehicles/:id  (owner)
Body: any subset of the POST fields (at least one). Limits are checked on the merged result.
200 → Vehicle. Errors: 404, 409 `CONFLICT` (plate), 422.

### PATCH /api/v1/vehicles/:id/active  (owner)
Body `{ "isActive": false }` → 200 Vehicle.
Errors: 409 `INVALID_STATE` (deactivating with SCHEDULED / IN_PROGRESS trips), 403 `FORBIDDEN` (activating a vehicle an admin deactivated).

### POST /api/v1/vehicles/:id/documents  (owner) — multipart/form-data
Fields: `docType` (enum above), `file` (jpg/png/pdf, ≤ 5 MB, type checked from the file's content). Re-upload of the same `docType` replaces the old file (same document id, status back to `UPLOADED`).
201 → VehicleDocument. Errors: 400 `FILE_INVALID` (file type or size), 404, 422 (bad docType / no file).

### GET /api/v1/vehicles/:id/documents  (owner or ADMIN)
200 → `VehicleDocument[]`.

### GET /api/v1/vehicles/:id/verification  (owner or ADMIN)
200 →
```json
{ "vehicleId": "uuid", "status": "NOT_SUBMITTED", "missingDocuments": ["INSURANCE"], "rejectionReason": null, "verifiedAt": null, "documents": [ … ] }
```
`missingDocuments` = required types not uploaded or `REJECTED`.

### POST /api/v1/vehicles/:id/verification/submit  (owner)
`NOT_SUBMITTED | REJECTED → PENDING`. 200 → same shape as GET verification.
Errors: 409 `INVALID_STATE` (already PENDING / APPROVED), 422 `VALIDATION_ERROR` with `details: [{ field: "documents", docType, message }]` when required documents are missing.

---

## Admin endpoints — `/api/v1/admin/vehicles` (role ADMIN)

### GET /api/v1/admin/vehicles
Query: `verificationStatus`, `type`, `q` (plate / make / model / owner name / phone), `isActive` (`true|false`), `page`, `limit` (max 100).
200 → `data: (Vehicle & { owner: { id, fullName, phone } })[]`, `meta: { page, limit, total, totalPages }`.
`verificationStatus=PENDING` is sorted oldest-waiting first; otherwise newest first.

### GET /api/v1/admin/vehicles/:id
200 → Vehicle + `owner: { id, fullName, phone, driverVerificationStatus }` + `documents[]` + `missingDocuments[]`.
(`driverVerificationStatus` comes from `driver_profiles`, `null` if the owner has no driver profile.)

### PATCH /api/v1/admin/vehicles/:id/verification
Body:
```json
{ "decision": "APPROVE | REJECT", "reason": "Insurance expired", "documents": [{ "id": "uuid", "status": "ACCEPTED | REJECTED" }] }
```
- `reason` required for REJECT (≥ 3 chars); stored as `rejectionReason`.
- only from `PENDING`, else 409 `INVALID_STATE`.
- APPROVE fails with 422 if a required document is missing/rejected; all remaining `UPLOADED` documents become `ACCEPTED`.
- Runs in one DB transaction; writes audit log `VEHICLE_APPROVED` / `VEHICLE_REJECTED`.
200 → same shape as GET detail.

### PATCH /api/v1/admin/vehicles/:id/status
Body `{ "isActive": false, "reason": "Fake documents" }` (`reason` required when deactivating).
200 → Vehicle. 409 `INVALID_STATE` if the vehicle has SCHEDULED / IN_PROGRESS trips. Audit `VEHICLE_ADMIN_DEACTIVATED` / `VEHICLE_ADMIN_ACTIVATED`.

---

## Audit actions written (entity_type `VEHICLE`)
`VEHICLE_CREATED`, `VEHICLE_UPDATED`, `VEHICLE_REVERIFICATION_REQUIRED`, `VEHICLE_DOCUMENT_UPLOADED`, `VEHICLE_SUBMITTED`,
`VEHICLE_APPROVED`, `VEHICLE_REJECTED`, `VEHICLE_ACTIVATED`, `VEHICLE_DEACTIVATED`, `VEHICLE_ADMIN_ACTIVATED`, `VEHICLE_ADMIN_DEACTIVATED`.

## DB (migration `301_create_vehicle_tables.sql`)
`vehicles` and `vehicle_documents` as team contract A6, except that `vehicle_documents.file_url` is `storage_key`: files are private, so the table keeps the storage key and the API builds a signed link, as `driver_documents` does. Also:
CHECKs (`passenger_seats >= 1 AND passenger_seats < total_seats`, cargo ≥ 0, enums), indexes on `driver_user_id` and `verification_status`,
UNIQUE `(vehicle_id, doc_type)` on `vehicle_documents`. `vehicle_documents.status` default `UPLOADED`.

## For Member 4 (trips)
```js
const { isVehicleUsable, getUsableVehicle } = require('../vehicles/vehicle.service');
const vehicle = await getUsableVehicle(vehicleId, req.user.id); // null if not owner / not APPROVED / inactive
// vehicle.passengerSeats = max seatsOffered, vehicle.cargoCapacityKg = max cargo
```
