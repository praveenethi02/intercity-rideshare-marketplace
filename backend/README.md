# Intercity Rideshare API

Node.js and Express monolith with PostgreSQL. This covers authentication, accounts and access control (Jira epic SCRUM-5). Other modules build on it.

## Run it locally

Needs Node.js 20 or newer and PostgreSQL. `docker compose up -d` starts a suitable database.

```bash
cd backend
npm install
cp .env.example .env     # then fill in JWT_ACCESS_SECRET and OTP_HMAC_SECRET
npm run migrate
npm run seed:admin       # optional: needs ADMIN_PHONE and ADMIN_PASSWORD in .env
npm run dev
```

The API runs on `http://localhost:4000`. In development, OTP codes are printed to the server log instead of being sent by SMS.

## Tests

```bash
npm test
```

Tests use PGlite, a PostgreSQL that runs inside the test process, so they need no database or `.env`.

GitHub Actions runs these tests on every pull request that changes the backend. It also applies the migrations to a real PostgreSQL 16 server, seeds the admin account and checks that the server starts.

## Response format

Every response has the same shape:

```json
{ "success": true, "message": "Login successful", "data": {}, "meta": null }
```

Errors put a machine-readable code in `meta`:

```json
{
  "success": false,
  "message": "Request validation failed",
  "data": null,
  "meta": { "code": "VALIDATION_ERROR", "details": [{ "field": "body.phone", "message": "..." }] }
}
```

## Endpoints

All paths start with `/api/v1`. "Bearer" means the request needs an `Authorization: Bearer <accessToken>` header.

| Method | Path | Access | Purpose |
| --- | --- | --- | --- |
| POST | `/auth/register` | Public | Create an account and text a code |
| POST | `/auth/otp/verify` | Public | Confirm the code, activate the account, return tokens |
| POST | `/auth/otp/resend` | Public | Send a new registration code |
| POST | `/auth/login` | Public | Log in with phone and password |
| POST | `/auth/refresh` | Public | Exchange a refresh token for new tokens |
| POST | `/auth/reactivate` | Public | Reopen a self-deactivated account |
| POST | `/auth/password/forgot` | Public | Text a password reset code |
| POST | `/auth/password/reset` | Public | Set a new password using the code |
| POST | `/auth/password/change` | Bearer | Change the password |
| POST | `/auth/logout` | Bearer | Sign out this device |
| POST | `/auth/logout-all` | Bearer | Sign out every device |
| GET | `/users/me` | Bearer | View profile |
| PATCH | `/users/me` | Bearer | Edit name, email or avatar |
| PUT | `/users/me/role` | Bearer | Switch between Passenger, Driver and Cargo Customer |
| POST | `/users/me/deactivate` | Bearer | Close the account (needs the password) |
| GET | `/admin/users` | Admin | List users: `role`, `status`, `search`, `page`, `limit` |
| GET | `/admin/users/:id` | Admin | View a user |
| PATCH | `/admin/users/:id/status` | Admin | Set `ACTIVE` or `SUSPENDED` |

## Protecting routes in your module

```js
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const { ROLES } = require('../users/user.constants');

router.post('/vehicles', authenticate, requireRole(ROLES.DRIVER), createVehicle);
```

`authenticate` sets `req.user` from the database, so role and status are always current, and rejects signed-out sessions and closed accounts.

## Adding a module

- Put code in `src/modules/<name>/` and mount its routes in `src/app.js`.
- Add schema changes as a new numbered file in `migrations/`. Never edit a migration that has been merged.
- Validate input with `validate({ body: schema })` and read it from `req.validated`.
- Throw `ApiError` for expected failures and send successes with `respond`.

## Security decisions

- **Passwords:** bcrypt. Hashes are never returned by the API.
- **Access tokens:** JWT, 15 minutes. Each request also checks the session, so logout and suspension apply immediately.
- **Refresh tokens:** stored hashed and replaced on every use. Reusing an old one ends the session.
- **OTP codes:** stored as an HMAC. They expire after 5 minutes, allow 5 attempts, and have a 60-second resend cooldown and an hourly limit of 5.
- **ADMIN role:** cannot be self-selected. It is only created by `npm run seed:admin`.
- **Rate limiting:** per IP on `/auth`, held in memory. Moving to several API instances needs a shared store such as Redis.

## Before production

Add a real SMS provider in `src/services/sms.js`. The server refuses to start with `SMS_PROVIDER=console` when `NODE_ENV=production`.
