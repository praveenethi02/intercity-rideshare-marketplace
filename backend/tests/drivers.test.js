const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Must be set before the app loads its configuration.
const uploadDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rideshare-uploads-'));
process.env.UPLOAD_DIR = uploadDir;

const request = require('supertest');
const db = require('../src/db');
const seedAdmin = require('../src/db/seed-admin');
const driverService = require('../src/modules/drivers/driver.service');
const { app, post, get, patch, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(async () => {
  await stopTestDb();
  fs.rmSync(uploadDir, { recursive: true, force: true });
});

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(32),
]);
const ALL_DOCUMENTS = ['LICENCE_FRONT', 'LICENCE_BACK', 'NIC_FRONT', 'NIC_BACK', 'PROFILE_PHOTO'];
const ADMIN = { ADMIN_NAME: 'System Admin', ADMIN_PHONE: '0770000001', ADMIN_PASSWORD: 'Adm1nPassword' };

let nextIdentity = 100000;

function registration(overrides = {}) {
  nextIdentity += 1;
  return {
    licenceNumber: `B${nextIdentity}`,
    licenceExpiry: '2099-01-31',
    nic: `199912${nextIdentity}`,
    ...overrides,
  };
}

async function signedInAdmin() {
  await seedAdmin(ADMIN);
  const res = await post('/auth/login', { phone: ADMIN.ADMIN_PHONE, password: ADMIN.ADMIN_PASSWORD });
  return { user: res.body.data.user, token: res.body.data.tokens.accessToken };
}

async function newDriver(overrides = {}) {
  const { user, tokens } = await signedInUser(overrides);
  const res = await post('/drivers', registration(), tokens.accessToken);
  expect(res.status).toBe(201);
  return { id: user.id, token: tokens.accessToken };
}

const upload = (token, type, file = PNG, name = 'upload.png') =>
  request(app)
    .post('/api/v1/drivers/me/documents')
    .set('Authorization', `Bearer ${token}`)
    .field('type', type)
    .attach('file', file, name);

async function submittedDriver(overrides = {}) {
  const driver = await newDriver(overrides);
  for (const type of ALL_DOCUMENTS) {
    expect((await upload(driver.token, type)).status).toBe(201);
  }
  const { rows } = await db.query(
    "SELECT id FROM verification_requests WHERE subject_id = $1 AND status = 'PENDING'",
    [driver.id],
  );
  return { ...driver, requestId: rows[0].id };
}

async function approvedDriver(adminToken, overrides = {}) {
  const driver = await submittedDriver(overrides);
  const res = await patch(`/admin/verifications/${driver.requestId}`, adminToken, {
    decision: 'APPROVED',
  });
  expect(res.status).toBe(200);
  return driver;
}

const profileOf = async (token) => (await get('/drivers/me', token)).body.data.driver;
const auditActions = async (entityId) =>
  (await db.query('SELECT action FROM audit_logs WHERE entity_id = $1', [entityId])).rows.map(
    (row) => row.action,
  );

describe('POST /drivers (SCRUM-38)', () => {
  test('creates a pending profile, sets the DRIVER role and never returns the NIC', async () => {
    const { user, tokens } = await signedInUser({ role: 'PASSENGER' });
    const body = registration({
      dateOfBirth: '1990-05-20',
      address: '12 Galle Road, Colombo',
      emergencyContactName: 'Kamal Silva',
      emergencyContactPhone: '0771234567',
    });

    const res = await post('/drivers', body, tokens.accessToken);

    expect(res.status).toBe(201);
    expect(res.body.data.driver).toMatchObject({
      id: user.id,
      userId: user.id,
      licenceExpiry: '2099-01-31',
      dateOfBirth: '1990-05-20',
      emergencyContactPhone: '+94771234567',
      verification: 'PENDING',
      accountStatus: 'ACTIVE',
      documents: [],
    });
    expect(JSON.stringify(res.body)).not.toContain(body.nic);
    expect((await get('/users/me', tokens.accessToken)).body.data.user.role).toBe('DRIVER');
  });

  test('requires a token', async () => {
    expect((await post('/drivers', registration())).status).toBe(401);
  });

  test.each([
    ['an expired licence', { licenceExpiry: '2001-01-01' }],
    ['an impossible date', { licenceExpiry: '2099-02-31' }],
    ['a bad NIC', { nic: '12345' }],
    ['a bad licence number', { licenceNumber: '!' }],
    ['an under-18 driver', { dateOfBirth: new Date().toISOString().slice(0, 10) }],
    ['an unknown field', { role: 'ADMIN' }],
  ])('rejects %s', async (_name, overrides) => {
    const { tokens } = await signedInUser();

    const res = await post('/drivers', registration(overrides), tokens.accessToken);

    expect(res.status).toBe(422);
    expect(res.body.meta.code).toBe('VALIDATION_ERROR');
  });

  test('rejects a second registration', async () => {
    const driver = await newDriver();

    const res = await post('/drivers', registration(), driver.token);

    expect(res.status).toBe(409);
    expect(res.body.meta.code).toBe('DRIVER_EXISTS');
  });

  test("rejects another driver's licence and leaves the user's role unchanged", async () => {
    const first = await signedInUser();
    const body = registration();
    await post('/drivers', body, first.tokens.accessToken);
    const second = await signedInUser({ role: 'PASSENGER' });

    const res = await post(
      '/drivers',
      registration({ licenceNumber: body.licenceNumber }),
      second.tokens.accessToken,
    );

    expect(res.status).toBe(409);
    expect(res.body.meta.code).toBe('IDENTITY_IN_USE');
    expect((await get('/users/me', second.tokens.accessToken)).body.data.user.role).toBe('PASSENGER');
  });

  test('an admin cannot become a driver', async () => {
    const { token } = await signedInAdmin();

    const res = await post('/drivers', registration(), token);

    expect(res.status).toBe(403);
    expect(res.body.meta.code).toBe('ADMIN_ROLE_LOCKED');
  });
});

describe('driver profile (SCRUM-39)', () => {
  test('non-drivers cannot use driver routes', async () => {
    const { tokens } = await signedInUser();

    for (const route of ['me', 'me/verification', 'me/trips', 'me/earnings']) {
      const res = await get(`/drivers/${route}`, tokens.accessToken);
      expect(res.status).toBe(403);
    }
    expect((await patch('/drivers/me', tokens.accessToken, { address: 'x' })).status).toBe(403);
    expect((await upload(tokens.accessToken, 'NIC_FRONT')).status).toBe(403);
  });

  test('a driver who switches role can still reach their driver details', async () => {
    const driver = await newDriver();

    await request(app)
      .put('/api/v1/users/me/role')
      .set('Authorization', `Bearer ${driver.token}`)
      .send({ role: 'PASSENGER' });

    expect((await get('/drivers/me', driver.token)).status).toBe(200);
  });

  test('contact and bank changes keep an approved driver approved and hide bank details', async () => {
    const admin = await signedInAdmin();
    const driver = await approvedDriver(admin.token);

    const res = await patch('/drivers/me', driver.token, {
      address: 'New address',
      bankAccount: { bank: 'BOC', branch: 'Kandy', accountNumber: '9876543210', accountName: 'N Silva' },
    });

    expect(res.status).toBe(200);
    expect(res.body.data.driver).toMatchObject({ address: 'New address', verification: 'APPROVED' });
    expect(JSON.stringify(res.body)).not.toContain('9876543210');
  });

  test('changing the licence after approval returns to review and is audited', async () => {
    const admin = await signedInAdmin();
    const driver = await approvedDriver(admin.token);

    const res = await patch('/drivers/me', driver.token, { licenceExpiry: '2098-01-01' });

    expect(res.body.data.driver).toMatchObject({
      licenceExpiry: '2098-01-01',
      verification: 'PENDING',
      verifiedAt: null,
    });
    expect(await auditActions(driver.id)).toContain('DRIVER_LICENCE_CHANGED_AFTER_APPROVAL');

    const queue = await get('/admin/verifications?status=PENDING', admin.token);
    expect(queue.body.data.verifications.map((v) => v.subjectId)).toEqual([driver.id]);
  });

  test('sending the same licence details changes nothing', async () => {
    const admin = await signedInAdmin();
    const driver = await approvedDriver(admin.token);

    const res = await patch('/drivers/me', driver.token, { licenceExpiry: '2099-01-31' });

    expect(res.body.data.driver.verification).toBe('APPROVED');
  });

  test("rejects another driver's licence number and an empty update", async () => {
    const first = await signedInUser();
    const body = registration();
    await post('/drivers', body, first.tokens.accessToken);
    const driver = await newDriver();

    const taken = await patch('/drivers/me', driver.token, { licenceNumber: body.licenceNumber });
    expect(taken.status).toBe(409);
    expect(taken.body.meta.code).toBe('IDENTITY_IN_USE');

    expect((await patch('/drivers/me', driver.token, {})).status).toBe(422);
  });

  test('the public profile shortens the name and hides licence and NIC', async () => {
    const body = registration();
    const { user, tokens } = await signedInUser({ fullName: 'Nimal Perera Silva' });
    await post('/drivers', body, tokens.accessToken);
    const viewer = await signedInUser();

    const res = await get(`/drivers/${user.id}`, viewer.tokens.accessToken);

    expect(res.status).toBe(200);
    expect(res.body.data.driver).toMatchObject({
      id: user.id,
      fullName: 'Nimal S.',
      verifiedDriver: false,
      completedTrips: 0,
    });
    expect(JSON.stringify(res.body)).not.toContain(body.nic);
    expect(JSON.stringify(res.body)).not.toContain(body.licenceNumber);
  });

  test('the public profile needs a token, a valid id and a known driver', async () => {
    const { tokens } = await signedInUser();
    const unknown = '00000000-0000-4000-8000-000000000000';

    expect((await get(`/drivers/${unknown}`)).status).toBe(401);
    expect((await get('/drivers/not-a-uuid', tokens.accessToken)).status).toBe(422);
    const res = await get(`/drivers/${unknown}`, tokens.accessToken);
    expect(res.status).toBe(404);
    expect(res.body.meta.code).toBe('DRIVER_NOT_FOUND');
  });
});

describe('document upload (SCRUM-40, SCRUM-41)', () => {
  test('stores a document and returns a working signed link', async () => {
    const driver = await newDriver();

    const res = await upload(driver.token, 'LICENCE_FRONT');

    expect(res.status).toBe(201);
    expect(res.body.data.document.type).toBe('LICENCE_FRONT');

    const { pathname, search } = new URL(res.body.data.document.url);
    const file = await request(app).get(`${pathname}${search}`);
    expect(file.status).toBe(200);
    expect(file.headers['cache-control']).toBe('private, no-store');
    expect(file.headers['x-content-type-options']).toBe('nosniff');
  });

  test('rejects tampered, expired and unsigned links', async () => {
    const driver = await newDriver();
    const res = await upload(driver.token, 'LICENCE_FRONT');
    const url = new URL(res.body.data.document.url);

    const tampered = new URLSearchParams(url.search);
    tampered.set('expires', String(Number(tampered.get('expires')) + 1000));
    expect((await request(app).get(`${url.pathname}?${tampered}`)).status).toBe(403);

    const expired = new URLSearchParams(url.search);
    expired.set('expires', '1000');
    expect((await request(app).get(`${url.pathname}?${expired}`)).status).toBe(403);

    expect((await request(app).get(url.pathname)).status).toBe(403);
  });

  test('judges the file by its content, not its name', async () => {
    const driver = await newDriver();

    const res = await upload(driver.token, 'NIC_FRONT', Buffer.from('<script>'), 'photo.png');

    expect(res.status).toBe(400);
    expect(res.body.meta.code).toBe('FILE_INVALID');
    expect((await profileOf(driver.token)).documents).toEqual([]);
  });

  test('rejects a file over 5 MB', async () => {
    const driver = await newDriver();
    const tooBig = Buffer.concat([PNG, Buffer.alloc(5 * 1024 * 1024)]);

    const res = await upload(driver.token, 'NIC_FRONT', tooBig);

    expect(res.status).toBe(400);
    expect(res.body.meta.code).toBe('FILE_INVALID');
  });

  test('rejects an unknown type and a missing file', async () => {
    const driver = await newDriver();

    expect((await upload(driver.token, 'PASSPORT')).status).toBe(422);

    const noFile = await request(app)
      .post('/api/v1/drivers/me/documents')
      .set('Authorization', `Bearer ${driver.token}`)
      .field('type', 'NIC_FRONT');
    expect(noFile.status).toBe(422);
  });

  test('uploading the same type again replaces the document and removes the old file', async () => {
    const driver = await newDriver();
    await upload(driver.token, 'NIC_BACK');
    const filesBefore = fs.readdirSync(uploadDir).length;

    await upload(driver.token, 'NIC_BACK');

    expect((await profileOf(driver.token)).documents).toHaveLength(1);
    expect(fs.readdirSync(uploadDir)).toHaveLength(filesBefore);
  });

  test('a new identity document returns an approved driver to review, a new photo does not', async () => {
    const admin = await signedInAdmin();
    const driver = await approvedDriver(admin.token);

    await upload(driver.token, 'PROFILE_PHOTO');
    expect((await profileOf(driver.token)).verification).toBe('APPROVED');

    await upload(driver.token, 'NIC_FRONT');
    expect((await profileOf(driver.token)).verification).toBe('PENDING');
  });
});

describe('verification status (SCRUM-42)', () => {
  test('lists what is missing and joins the queue only when everything is uploaded', async () => {
    const admin = await signedInAdmin();
    const driver = await newDriver();

    const before = await get('/drivers/me/verification', driver.token);
    expect(before.body.data.verification).toMatchObject({
      id: null,
      type: 'DRIVER',
      subjectId: driver.id,
      status: 'PENDING',
      missingDocuments: ALL_DOCUMENTS,
    });

    for (const type of ALL_DOCUMENTS.slice(0, 4)) await upload(driver.token, type);
    expect((await get('/admin/verifications', admin.token)).body.meta.total).toBe(0);

    await upload(driver.token, 'PROFILE_PHOTO');
    expect((await get('/admin/verifications', admin.token)).body.meta.total).toBe(1);

    const after = await get('/drivers/me/verification', driver.token);
    expect(after.body.data.verification.missingDocuments).toEqual([]);
    expect(after.body.data.verification.id).not.toBeNull();
    expect(after.body.data.verification.documents).toHaveLength(5);
  });
});

describe('admin verification (SCRUM-43)', () => {
  test('only admins can use the queue', async () => {
    const driver = await submittedDriver();
    const { requestId } = driver;

    expect((await get('/admin/verifications')).status).toBe(401);
    expect((await get('/admin/verifications', driver.token)).status).toBe(403);
    const decide = await patch(`/admin/verifications/${requestId}`, driver.token, {
      decision: 'APPROVED',
    });
    expect(decide.status).toBe(403);
  });

  test('lists requests oldest first with documents, filters and paging', async () => {
    const admin = await signedInAdmin();
    const first = await submittedDriver();
    const second = await submittedDriver();

    const res = await get('/admin/verifications?status=PENDING&type=DRIVER', admin.token);

    expect(res.status).toBe(200);
    expect(res.body.meta).toEqual({ page: 1, limit: 20, total: 2, totalPages: 1 });
    expect(res.body.data.verifications.map((v) => v.subjectId)).toEqual([first.id, second.id]);
    expect(res.body.data.verifications[0].documents).toHaveLength(5);

    const paged = await get('/admin/verifications?limit=1&page=2', admin.token);
    expect(paged.body.data.verifications.map((v) => v.subjectId)).toEqual([second.id]);

    expect((await get('/admin/verifications?type=VEHICLE', admin.token)).body.meta.total).toBe(0);
    expect((await get('/admin/verifications?status=NOPE', admin.token)).status).toBe(422);
  });

  test('approving updates the driver and writes an audit log', async () => {
    const admin = await signedInAdmin();
    const driver = await submittedDriver();

    const res = await patch(`/admin/verifications/${driver.requestId}`, admin.token, {
      decision: 'APPROVED',
      reason: 'ignored',
    });

    expect(res.status).toBe(200);
    expect(res.body.data.verification).toMatchObject({
      status: 'APPROVED',
      reason: null,
      decidedBy: admin.user.id,
    });
    const profile = await profileOf(driver.token);
    expect(profile.verification).toBe('APPROVED');
    expect(profile.verifiedAt).not.toBeNull();
    expect(await auditActions(driver.requestId)).toEqual(['VERIFICATION_APPROVED']);
  });

  test('rejecting needs a reason, shows it to the driver and allows another try', async () => {
    const admin = await signedInAdmin();
    const driver = await submittedDriver();
    const url = `/admin/verifications/${driver.requestId}`;

    expect((await patch(url, admin.token, { decision: 'REJECTED' })).status).toBe(422);

    const res = await patch(url, admin.token, { decision: 'REJECTED', reason: 'Blurry licence' });
    expect(res.status).toBe(200);

    const rejected = await profileOf(driver.token);
    expect(rejected).toMatchObject({ verification: 'REJECTED', rejectionReason: 'Blurry licence' });

    await upload(driver.token, 'LICENCE_FRONT');

    const reopened = await profileOf(driver.token);
    expect(reopened).toMatchObject({ verification: 'PENDING', rejectionReason: null });
    const queue = await get('/admin/verifications?status=PENDING', admin.token);
    expect(queue.body.meta.total).toBe(1);
  });

  test('a request can be decided only once', async () => {
    const admin = await signedInAdmin();
    const driver = await submittedDriver();
    const url = `/admin/verifications/${driver.requestId}`;
    await patch(url, admin.token, { decision: 'APPROVED' });

    const res = await patch(url, admin.token, { decision: 'REJECTED', reason: 'Too late' });

    expect(res.status).toBe(409);
    expect(res.body.meta.code).toBe('INVALID_STATUS');
    expect((await profileOf(driver.token)).verification).toBe('APPROVED');
  });

  test('handles unknown ids, bad ids and vehicle requests', async () => {
    const admin = await signedInAdmin();
    const body = { decision: 'APPROVED' };

    const unknown = await patch(
      '/admin/verifications/00000000-0000-4000-8000-000000000000',
      admin.token,
      body,
    );
    expect(unknown.status).toBe(404);
    expect((await patch('/admin/verifications/not-a-uuid', admin.token, body)).status).toBe(422);

    const { rows } = await db.query(
      "INSERT INTO verification_requests (type, subject_id) VALUES ('VEHICLE', gen_random_uuid()) RETURNING id",
    );
    const vehicle = await patch(`/admin/verifications/${rows[0].id}`, admin.token, body);
    expect(vehicle.status).toBe(409);
  });

  test("the existing admin user routes still work alongside the drivers' admin routes", async () => {
    const admin = await signedInAdmin();
    const driver = await newDriver();

    expect((await get('/admin/users', admin.token)).status).toBe(200);
    expect((await get('/admin/users', driver.token)).status).toBe(403);
    expect((await get('/admin/users')).status).toBe(401);
  });
});

describe('driver rating (SCRUM-46)', () => {
  test('keeps a running average that appears in the profile', async () => {
    const driver = await newDriver();

    expect(await driverService.applyRating(driver.id, 5)).toEqual({ averageRating: 5, ratingCount: 1 });
    expect(await driverService.applyRating(driver.id, 4)).toEqual({ averageRating: 4.5, ratingCount: 2 });
    expect(await driverService.applyRating(driver.id, 3)).toEqual({ averageRating: 4, ratingCount: 3 });

    expect(await profileOf(driver.token)).toMatchObject({ averageRating: 4, ratingCount: 3 });
  });

  test.each([0, 6, 4.5, '5'])('rejects %p stars', async (stars) => {
    const driver = await newDriver();

    await expect(driverService.applyRating(driver.id, stars)).rejects.toMatchObject({ status: 422 });
  });

  test('rejects an unknown driver', async () => {
    await expect(
      driverService.applyRating('00000000-0000-4000-8000-000000000000', 5),
    ).rejects.toMatchObject({ status: 404 });
  });
});

describe('driver account status (SCRUM-47)', () => {
  const url = (id) => `/admin/drivers/${id}/account-status`;

  test('only admins can change it', async () => {
    const driver = await newDriver();

    expect((await patch(url(driver.id), undefined, { status: 'ACTIVE' })).status).toBe(401);
    expect((await patch(url(driver.id), driver.token, { status: 'ACTIVE' })).status).toBe(403);
  });

  test('suspending blocks eligibility and is audited; activating restores it', async () => {
    const admin = await signedInAdmin();
    const driver = await approvedDriver(admin.token);
    expect(await driverService.isDriverEligible(driver.id)).toBe(true);

    const suspended = await patch(url(driver.id), admin.token, {
      status: 'SUSPENDED',
      reason: 'Under investigation',
    });
    expect(suspended.status).toBe(200);
    expect(suspended.body.data.driver.accountStatus).toBe('SUSPENDED');
    expect(await driverService.isDriverEligible(driver.id)).toBe(false);
    expect(await auditActions(driver.id)).toContain('DRIVER_ACCOUNT_SUSPENDED');

    await patch(url(driver.id), admin.token, { status: 'ACTIVE' });
    expect(await driverService.isDriverEligible(driver.id)).toBe(true);
  });

  test('a driver who is not approved is not eligible', async () => {
    const driver = await newDriver();

    expect(await driverService.isDriverEligible(driver.id)).toBe(false);
    expect(await driverService.isDriverEligible('00000000-0000-4000-8000-000000000000')).toBe(false);
  });

  test('validates the request', async () => {
    const admin = await signedInAdmin();
    const driver = await newDriver();

    expect((await patch(url(driver.id), admin.token, { status: 'SUSPENDED' })).status).toBe(422);
    expect((await patch(url(driver.id), admin.token, { status: 'NOPE' })).status).toBe(422);
    expect((await patch(url('not-a-uuid'), admin.token, { status: 'ACTIVE' })).status).toBe(422);
    const unknown = await patch(url('00000000-0000-4000-8000-000000000000'), admin.token, {
      status: 'ACTIVE',
    });
    expect(unknown.status).toBe(404);
  });
});

describe('before the trip module is merged (SCRUM-44, SCRUM-45)', () => {
  test('trip history is empty and earnings are zero', async () => {
    const driver = await newDriver();

    const trips = await get('/drivers/me/trips', driver.token);
    expect(trips.status).toBe(200);
    expect(trips.body.data.trips).toEqual([]);
    expect(trips.body.meta).toEqual({ page: 1, limit: 20, total: 0, totalPages: 0 });

    const earnings = await get('/drivers/me/earnings', driver.token);
    expect(earnings.body.data.earnings).toEqual({
      currency: 'LKR',
      seatEarnings: 0,
      cargoEarnings: 0,
      platformFees: 0,
      paidOut: 0,
      pendingPayout: 0,
      completedTrips: 0,
      periodFrom: null,
      periodTo: null,
    });
  });
});

describe('with the agreed trips table (SCRUM-44, SCRUM-45)', () => {
  // Stands in for the trip module's migration, using the columns in the team contract.
  beforeAll(async () => {
    await db.exec(`
      CREATE TABLE trips (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        driver_user_id UUID NOT NULL REFERENCES users (id),
        vehicle_id UUID,
        origin_name TEXT,
        destination_name TEXT,
        departure_at TIMESTAMPTZ NOT NULL,
        estimated_arrival_at TIMESTAMPTZ,
        pricing_mode TEXT DEFAULT 'AUCTION',
        base_price_cents INT,
        seats_offered INT,
        seats_available INT,
        distance_m INT,
        duration_s INT,
        status TEXT NOT NULL DEFAULT 'SCHEDULED',
        cancel_reason TEXT,
        started_at TIMESTAMPTZ,
        completed_at TIMESTAMPTZ,
        cancelled_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);
  });

  const addTrip = (driverId, departure, status, completedAt = null) =>
    db.query(
      `INSERT INTO trips (driver_user_id, origin_name, destination_name, departure_at, status, completed_at)
       VALUES ($1, 'Kandy', 'Colombo', $2, $3, $4)`,
      [driverId, departure, status, completedAt],
    );

  test('lists only my trips, newest first, with a status filter and paging', async () => {
    const driver = await newDriver();
    const other = await newDriver();
    await addTrip(driver.id, '2026-01-01T08:00:00Z', 'COMPLETED', '2026-01-01T12:00:00Z');
    await addTrip(driver.id, '2026-03-01T08:00:00Z', 'SCHEDULED');
    await addTrip(other.id, '2026-02-01T08:00:00Z', 'SCHEDULED');

    const all = await get('/drivers/me/trips', driver.token);
    expect(all.body.meta.total).toBe(2);
    expect(all.body.data.trips.map((t) => t.status)).toEqual(['SCHEDULED', 'COMPLETED']);
    expect(all.body.data.trips[0]).toMatchObject({ originName: 'Kandy', destinationName: 'Colombo' });

    const completed = await get('/drivers/me/trips?status=COMPLETED', driver.token);
    expect(completed.body.data.trips.map((t) => t.status)).toEqual(['COMPLETED']);

    const paged = await get('/drivers/me/trips?limit=1&page=2', driver.token);
    expect(paged.body.data.trips.map((t) => t.status)).toEqual(['COMPLETED']);
    expect(paged.body.meta).toEqual({ page: 2, limit: 1, total: 2, totalPages: 2 });

    expect((await get('/drivers/me/trips?status=NOPE', driver.token)).status).toBe(422);
  });

  test('completed trips count towards the profile and earnings, within the dates asked for', async () => {
    const driver = await newDriver();
    await addTrip(driver.id, '2026-01-10T08:00:00Z', 'COMPLETED', '2026-01-10T12:00:00Z');
    await addTrip(driver.id, '2026-02-10T08:00:00Z', 'COMPLETED', '2026-02-10T12:00:00Z');
    await addTrip(driver.id, '2026-02-11T08:00:00Z', 'CANCELLED');

    expect((await profileOf(driver.token)).completedTrips).toBe(2);

    const earnings = async (query) =>
      (await get(`/drivers/me/earnings${query}`, driver.token)).body.data.earnings;
    expect((await earnings('')).completedTrips).toBe(2);
    expect(await earnings('?from=2026-02-01&to=2026-02-10')).toMatchObject({
      completedTrips: 1,
      periodFrom: '2026-02-01',
      periodTo: '2026-02-10',
    });
    expect((await earnings('?to=2026-01-09')).completedTrips).toBe(0);

    const backwards = await get('/drivers/me/earnings?from=2026-02-02&to=2026-02-01', driver.token);
    expect(backwards.status).toBe(422);
    expect((await get('/drivers/me/earnings?from=soon', driver.token)).status).toBe(422);
  });
});
