# Driver Management API changes (SCRUM-38 to SCRUM-47)

For the PM to merge into `docs/api/openapi.yaml`. All paths start with `/api/v1`. Responses use the backend's standard `{ success, message, data, meta }` format, and errors put their code in `meta.code`.

## Endpoints

| Method | Path | Access | Task | `data` |
| --- | --- | --- | --- | --- |
| POST | `/drivers` | Bearer | SCRUM-38 | `driver` (201) |
| GET | `/drivers/me` | Driver | SCRUM-39 | `driver` |
| PATCH | `/drivers/me` | Driver | SCRUM-39 | `driver` |
| GET | `/drivers/:id` | Bearer | SCRUM-39 | `driver` (public fields only) |
| POST | `/drivers/me/documents` | Driver | SCRUM-40, 41 | `document` (201) |
| GET | `/drivers/me/verification` | Driver | SCRUM-42 | `verification` |
| GET | `/drivers/me/trips` | Driver | SCRUM-44 | `trips`, with paging in `meta` |
| GET | `/drivers/me/earnings` | Driver | SCRUM-45 | `earnings` |
| GET | `/admin/verifications` | Admin | SCRUM-43 | `verifications`, with paging in `meta` |
| PATCH | `/admin/verifications/:id` | Admin | SCRUM-43 | `verification` |
| PATCH | `/admin/drivers/:id/account-status` | Admin | SCRUM-47 | `driver` |
| GET | `/files/:key` | Signed link | SCRUM-40, 41 | The file |

A driver's `id` is their user id.

## Requests

**POST `/drivers`**: requires `licenceNumber`, `licenceExpiry` (`YYYY-MM-DD`) and `nic`. Optional: `dateOfBirth` (must be 18 or older), `address`, `emergencyContactName`, `emergencyContactPhone`.

**PATCH `/drivers/me`**: any of `licenceNumber`, `licenceExpiry`, `address`, `emergencyContactName`, `emergencyContactPhone`, and `bankAccount` (`bank`, `branch`, `accountNumber`, `accountName`).

**POST `/drivers/me/documents`**: `multipart/form-data` with `type` (`LICENCE_FRONT`, `LICENCE_BACK`, `NIC_FRONT`, `NIC_BACK`, `PROFILE_PHOTO`) and `file` (JPG, PNG or PDF, at most 5 MB).

**GET `/drivers/me/trips`**: `status` (`SCHEDULED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`), `page`, `limit`.

**GET `/drivers/me/earnings`**: `from` and `to` (`YYYY-MM-DD`).

**GET `/admin/verifications`**: `status`, `type` (`DRIVER`, `VEHICLE`), `page`, `limit`.

**PATCH `/admin/verifications/:id`**: `decision` (`APPROVED`, `REJECTED`) and `reason` (required when rejecting).

**PATCH `/admin/drivers/:id/account-status`**: `status` (`ACTIVE`, `SUSPENDED`, `DEACTIVATED`) and `reason` (required unless activating).

## Errors

| Status | Code | When |
| --- | --- | --- |
| 400 | `FILE_INVALID` | Not a real JPG, PNG or PDF, or over 5 MB |
| 403 | `FORBIDDEN` | Not a driver or not an admin, or a file link is invalid or expired |
| 403 | `ADMIN_ROLE_LOCKED` | An admin tried to register as a driver |
| 404 | `DRIVER_NOT_FOUND`, `VERIFICATION_NOT_FOUND`, `FILE_NOT_FOUND` | Unknown id or file |
| 409 | `DRIVER_EXISTS` | Already registered |
| 409 | `IDENTITY_IN_USE` | Licence or NIC belongs to another driver |
| 409 | `INVALID_STATUS` | Request already decided, or a vehicle request (not available yet) |
| 422 | `VALIDATION_ERROR` | Invalid input |

## Verification rules

1. A driver registers as `PENDING`.
2. A request joins the admin queue once all five documents are uploaded. There is no separate submit step.
3. An admin approves, or rejects with a reason.
4. Changing licence details or replacing a document returns the driver to `PENDING`. Bank details, contact details and, for an approved driver, a new profile photo do not.

## Differences from `openapi.yaml`

- Successful responses wrap the result in a named key (`data.driver`), matching the merged users and admin endpoints.
- Validation errors use 422, matching the merged backend.
- Added: `PATCH /admin/drivers/:id/account-status`, `GET /files/:key`, the optional registration and contact fields, `accountStatus`, `ratingCount`, `verifiedAt`, `missingDocuments`.
- Earnings adds `currency`, `completedTrips`, `periodFrom` and `periodTo`. The amounts stay at 0 until the payments module exists.
- Trip history uses the team contract's trip fields rather than the spec's `Trip` schema, and returns an empty list until the trip module adds its table.

## For other modules

- **Trips:** a driver may publish only if `driverService.isDriverEligible(userId)` is true, which means `verification_status = 'APPROVED'` and `account_status = 'ACTIVE'`.
- **Trips:** history and counts read `trips.driver_user_id`, `status` and `completed_at`, and the columns listed in `listTrips` in `driver.repository.js`.
- **Ratings:** call `driverService.applyRating(driverUserId, stars)`.
- **Vehicles:** `verification_requests` accepts `type = 'VEHICLE'`, and `decide` in `verification.service.js` needs extending for it.
- **Everyone:** migration `201` creates `audit_logs` if it does not exist yet.
