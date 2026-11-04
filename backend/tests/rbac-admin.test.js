const express = require('express');
const request = require('supertest');
const authenticate = require('../src/middleware/authenticate');
const requireRole = require('../src/middleware/require-role');
const { errorHandler } = require('../src/middleware/error');
const seedAdmin = require('../src/db/seed-admin');
const userRepository = require('../src/modules/users/user.repository');
const { PASSWORD, newUserData, post, get, patch, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const ADMIN = {
  ADMIN_NAME: 'System Admin',
  ADMIN_PHONE: '0770000001',
  ADMIN_PASSWORD: 'Adm1nPassword',
};

async function signedInAdmin() {
  await seedAdmin(ADMIN);
  const res = await post('/auth/login', {
    phone: ADMIN.ADMIN_PHONE,
    password: ADMIN.ADMIN_PASSWORD,
  });
  expect(res.status).toBe(200);
  return { user: res.body.data.user, token: res.body.data.tokens.accessToken };
}

describe('requireRole', () => {
  const guarded = express();
  guarded.get('/drivers-only', authenticate, requireRole('DRIVER'), (req, res) => res.json({}));
  guarded.get('/two-roles', authenticate, requireRole('DRIVER', 'ADMIN'), (req, res) => res.json({}));
  guarded.get('/no-auth-first', requireRole('DRIVER'), (req, res) => res.json({}));
  guarded.use(errorHandler);

  const call = (path, token) => {
    const req = request(guarded).get(path);
    return token ? req.set('Authorization', `Bearer ${token}`) : req;
  };

  test('allows a listed role and blocks others', async () => {
    const driver = await signedInUser({ role: 'DRIVER' });
    const passenger = await signedInUser({ role: 'PASSENGER' });

    expect((await call('/drivers-only', driver.tokens.accessToken)).status).toBe(200);

    const blocked = await call('/drivers-only', passenger.tokens.accessToken);
    expect(blocked.status).toBe(403);
    expect(blocked.body.meta.code).toBe('FORBIDDEN');
  });

  test('accepts any of several roles', async () => {
    const driver = await signedInUser({ role: 'DRIVER' });
    const admin = await signedInAdmin();
    const cargo = await signedInUser({ role: 'CARGO_CUSTOMER' });

    expect((await call('/two-roles', driver.tokens.accessToken)).status).toBe(200);
    expect((await call('/two-roles', admin.token)).status).toBe(200);
    expect((await call('/two-roles', cargo.tokens.accessToken)).status).toBe(403);
  });

  test('a role change applies at once to tokens already issued', async () => {
    const { tokens } = await signedInUser({ role: 'PASSENGER' });
    expect((await call('/drivers-only', tokens.accessToken)).status).toBe(403);

    await request(require('./helpers/api').app)
      .put('/api/v1/users/me/role')
      .set('Authorization', `Bearer ${tokens.accessToken}`)
      .send({ role: 'DRIVER' });

    expect((await call('/drivers-only', tokens.accessToken)).status).toBe(200);
  });

  test('without a token: 401, and fails closed if authenticate was forgotten', async () => {
    expect((await call('/drivers-only')).status).toBe(401);
    expect((await call('/no-auth-first')).status).toBe(401);
  });

  test('refuses to be configured with no roles', () => {
    expect(() => requireRole()).toThrow();
  });
});

describe('admin seed', () => {
  test('creates an active, verified admin who can log in', async () => {
    expect(await seedAdmin(ADMIN)).toBe(true);

    const { user } = await signedInAdmin();
    expect(user).toMatchObject({ role: 'ADMIN', status: 'ACTIVE' });
    expect(user.phoneVerifiedAt).not.toBeNull();
  });

  test('running it again changes nothing', async () => {
    await seedAdmin(ADMIN);

    expect(await seedAdmin({ ...ADMIN, ADMIN_PASSWORD: 'An0therPassword' })).toBe(false);

    const res = await post('/auth/login', {
      phone: ADMIN.ADMIN_PHONE,
      password: ADMIN.ADMIN_PASSWORD,
    });
    expect(res.status).toBe(200);
  });

  test('never promotes an existing user', async () => {
    const { data } = await signedInUser({ phone: ADMIN.ADMIN_PHONE });

    expect(await seedAdmin(ADMIN)).toBe(false);

    const res = await post('/auth/login', { phone: data.phone, password: PASSWORD });
    expect(res.body.data.user.role).toBe('PASSENGER');
  });

  test('rejects weak or missing details', async () => {
    await expect(seedAdmin({ ...ADMIN, ADMIN_PASSWORD: 'weak' })).rejects.toThrow(/ADMIN_PASSWORD/);
    await expect(seedAdmin({ ...ADMIN, ADMIN_PHONE: undefined })).rejects.toThrow(/ADMIN_PHONE/);
  });
});

describe('admin user management', () => {
  test.each(['PASSENGER', 'DRIVER', 'CARGO_CUSTOMER'])('%s gets 403', async (role) => {
    const { user, tokens } = await signedInUser({ role });
    const token = tokens.accessToken;

    expect((await get('/admin/users', token)).status).toBe(403);
    expect((await get(`/admin/users/${user.id}`, token)).status).toBe(403);
    expect(
      (await patch(`/admin/users/${user.id}/status`, token, { status: 'ACTIVE' })).status,
    ).toBe(403);
  });

  test('anonymous requests get 401', async () => {
    expect((await get('/admin/users')).status).toBe(401);
  });

  test('lists users without password hashes, with filters and paging', async () => {
    const { token } = await signedInAdmin();
    await signedInUser({ role: 'DRIVER', fullName: 'Nimal Driver' });
    await signedInUser({ role: 'DRIVER', fullName: 'Sunil Driver' });
    await signedInUser({ role: 'PASSENGER', fullName: '100% Passenger' });

    const all = await get('/admin/users', token);
    expect(all.status).toBe(200);
    expect(all.body.meta).toEqual({ page: 1, limit: 20, total: 4, totalPages: 1 });
    expect(JSON.stringify(all.body)).not.toMatch(/password/i);

    const drivers = await get('/admin/users?role=DRIVER', token);
    expect(drivers.body.meta.total).toBe(2);

    const paged = await get('/admin/users?role=DRIVER&limit=1&page=2', token);
    expect(paged.body.data.users).toHaveLength(1);
    expect(paged.body.meta).toMatchObject({ page: 2, limit: 1, total: 2, totalPages: 2 });

    const byName = await get('/admin/users?search=nimal', token);
    expect(byName.body.data.users.map((u) => u.fullName)).toEqual(['Nimal Driver']);

    const wildcard = await get(`/admin/users?search=${encodeURIComponent('%')}`, token);
    expect(wildcard.body.data.users.map((u) => u.fullName)).toEqual(['100% Passenger']);
  });

  test.each(['role=ROOT', 'status=NOPE', 'limit=1000', 'page=0', 'unknown=1'])(
    'rejects the query %s',
    async (query) => {
      const { token } = await signedInAdmin();

      expect((await get(`/admin/users?${query}`, token)).status).toBe(422);
    },
  );

  test('gets one user, with 404 for unknown ids and 422 for bad ones', async () => {
    const { token } = await signedInAdmin();
    const { user } = await signedInUser();

    expect((await get(`/admin/users/${user.id}`, token)).body.data.user.id).toBe(user.id);
    expect(
      (await get('/admin/users/00000000-0000-4000-8000-000000000000', token)).status,
    ).toBe(404);
    expect((await get('/admin/users/not-a-uuid', token)).status).toBe(422);
  });

  test('suspending signs the user out and blocks login; activating restores it', async () => {
    const { token } = await signedInAdmin();
    const { data, user, tokens } = await signedInUser();
    const credentials = { phone: data.phone, password: data.password };

    const suspended = await patch(`/admin/users/${user.id}/status`, token, { status: 'SUSPENDED' });
    expect(suspended.status).toBe(200);
    expect(suspended.body.data.user.status).toBe('SUSPENDED');

    expect((await get('/users/me', tokens.accessToken)).status).toBe(401);
    const login = await post('/auth/login', credentials);
    expect(login.status).toBe(403);
    expect(login.body.meta.code).toBe('ACCOUNT_SUSPENDED');

    const activated = await patch(`/admin/users/${user.id}/status`, token, { status: 'ACTIVE' });
    expect(activated.body.data.user.status).toBe('ACTIVE');
    expect((await post('/auth/login', credentials)).status).toBe(200);
  });

  test('an admin can reopen a self-deactivated account', async () => {
    const { token } = await signedInAdmin();
    const { user, tokens } = await signedInUser();
    await post('/users/me/deactivate', { password: PASSWORD }, tokens.accessToken);

    const res = await patch(`/admin/users/${user.id}/status`, token, { status: 'ACTIVE' });

    expect(res.body.data.user.status).toBe('ACTIVE');
  });

  test('setting the current status again is harmless', async () => {
    const { token } = await signedInAdmin();
    const { user } = await signedInUser();

    const res = await patch(`/admin/users/${user.id}/status`, token, { status: 'ACTIVE' });

    expect(res.status).toBe(200);
    expect(res.body.data.user.status).toBe('ACTIVE');
  });

  test('an unverified user cannot be activated by an admin', async () => {
    const { token } = await signedInAdmin();
    const data = newUserData();
    await post('/auth/register', data);
    const { id } = await userRepository.findByPhone(`+94${data.phone.slice(1)}`);

    const res = await patch(`/admin/users/${id}/status`, token, { status: 'ACTIVE' });

    expect(res.status).toBe(409);
    expect(res.body.meta.code).toBe('PHONE_NOT_VERIFIED');
  });

  test('an admin cannot change their own status or set other statuses', async () => {
    const { user, token } = await signedInAdmin();
    const other = await signedInUser();

    const own = await patch(`/admin/users/${user.id}/status`, token, { status: 'SUSPENDED' });
    expect(own.status).toBe(403);
    expect(own.body.meta.code).toBe('CANNOT_CHANGE_OWN_STATUS');

    const invalid = await patch(`/admin/users/${other.user.id}/status`, token, {
      status: 'PENDING_VERIFICATION',
    });
    expect(invalid.status).toBe(422);
  });
});
