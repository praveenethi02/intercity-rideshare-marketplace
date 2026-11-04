const db = require('../src/db');
const { PASSWORD, post, get, patch, put, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const me = (token) => get('/users/me', token);

describe('GET /users/me', () => {
  test('returns the signed-in user without the password hash', async () => {
    const { user, tokens } = await signedInUser({ fullName: 'Kasun Perera' });

    const res = await me(tokens.accessToken);

    expect(res.status).toBe(200);
    expect(res.body.data.user).toMatchObject({ id: user.id, fullName: 'Kasun Perera' });
    expect(JSON.stringify(res.body)).not.toMatch(/password/i);
  });

  test('requires being signed in', async () => {
    expect((await me()).status).toBe(401);
  });
});

describe('PATCH /users/me', () => {
  test('updates only the fields provided', async () => {
    const { tokens } = await signedInUser({ fullName: 'Old Name', email: 'old@example.com' });

    const res = await patch('/users/me', tokens.accessToken, { fullName: 'New Name' });

    expect(res.status).toBe(200);
    expect(res.body.data.user).toMatchObject({ fullName: 'New Name', email: 'old@example.com' });
  });

  test('null clears an optional field', async () => {
    const { tokens } = await signedInUser({ email: 'old@example.com' });

    const res = await patch('/users/me', tokens.accessToken, {
      email: null,
      avatarUrl: 'https://cdn.example.com/a.png',
    });

    expect(res.body.data.user).toMatchObject({
      email: null,
      avatarUrl: 'https://cdn.example.com/a.png',
    });
  });

  test.each([
    ['phone', { phone: '0771111111' }],
    ['role', { role: 'ADMIN' }],
    ['status', { status: 'ACTIVE' }],
    ['password hash', { password_hash: 'x' }],
    ['non-https avatar', { avatarUrl: 'http://example.com/a.png' }],
    ['script avatar', { avatarUrl: 'javascript:alert(1)' }],
    ['invalid email', { email: 'nope' }],
    ['empty body', {}],
  ])('rejects %s', async (_name, body) => {
    const { tokens } = await signedInUser();

    expect((await patch('/users/me', tokens.accessToken, body)).status).toBe(422);
  });

  test('rejects an email another user has', async () => {
    await signedInUser({ email: 'taken@example.com' });
    const { tokens } = await signedInUser();

    const res = await patch('/users/me', tokens.accessToken, { email: 'TAKEN@example.com' });

    expect(res.status).toBe(409);
  });
});

describe('PUT /users/me/role', () => {
  test('switches between selectable roles', async () => {
    const { tokens } = await signedInUser({ role: 'PASSENGER' });

    const res = await put('/users/me/role', tokens.accessToken, { role: 'DRIVER' });

    expect(res.status).toBe(200);
    expect(res.body.data.user.role).toBe('DRIVER');
    expect((await me(tokens.accessToken)).body.data.user.role).toBe('DRIVER');
  });

  test('cannot select ADMIN', async () => {
    const { tokens } = await signedInUser();

    expect((await put('/users/me/role', tokens.accessToken, { role: 'ADMIN' })).status).toBe(422);
  });

  test('an admin cannot change role', async () => {
    const { user, tokens } = await signedInUser();
    await db.query(`UPDATE users SET role = 'ADMIN' WHERE id = $1`, [user.id]);

    const res = await put('/users/me/role', tokens.accessToken, { role: 'PASSENGER' });

    expect(res.status).toBe(403);
    expect(res.body.meta.code).toBe('ADMIN_ROLE_LOCKED');
  });
});

describe('account deactivation and reactivation', () => {
  const deactivate = (token, password = PASSWORD) =>
    post('/users/me/deactivate', { password }, token);
  const credentials = ({ phone }, password = PASSWORD) => ({ phone, password });

  test('deactivating signs out and blocks login until reactivated', async () => {
    const { data, tokens } = await signedInUser();

    expect((await deactivate(tokens.accessToken)).status).toBe(200);

    expect((await me(tokens.accessToken)).status).toBe(401);
    expect((await post('/auth/refresh', { refreshToken: tokens.refreshToken })).status).toBe(401);

    const login = await post('/auth/login', credentials(data));
    expect(login.status).toBe(403);
    expect(login.body.meta.code).toBe('ACCOUNT_DEACTIVATED');

    const reopened = await post('/auth/reactivate', credentials(data));
    expect(reopened.status).toBe(200);
    expect(reopened.body.data.user.status).toBe('ACTIVE');
    expect((await me(reopened.body.data.tokens.accessToken)).status).toBe(200);
    expect((await post('/auth/login', credentials(data))).status).toBe(200);
  });

  test('deactivating requires the correct password', async () => {
    const { tokens } = await signedInUser();

    const res = await deactivate(tokens.accessToken, 'Wr0ngPass');

    expect(res.status).toBe(400);
    expect((await me(tokens.accessToken)).status).toBe(200);
  });

  test('reactivating requires the correct password', async () => {
    const { data, tokens } = await signedInUser();
    await deactivate(tokens.accessToken);

    expect((await post('/auth/reactivate', credentials(data, 'Wr0ngPass'))).status).toBe(401);
  });

  test('an active account cannot be reactivated', async () => {
    const { data } = await signedInUser();

    const res = await post('/auth/reactivate', credentials(data));

    expect(res.status).toBe(409);
  });

  test('a suspended account cannot reactivate itself', async () => {
    const { data, user } = await signedInUser();
    await db.query(`UPDATE users SET status = 'SUSPENDED' WHERE id = $1`, [user.id]);

    const res = await post('/auth/reactivate', credentials(data));

    expect(res.status).toBe(403);
    expect(res.body.meta.code).toBe('ACCOUNT_SUSPENDED');
  });

  test('a suspended user is blocked at once, even with a valid access token', async () => {
    const { user, tokens } = await signedInUser();
    await db.query(`UPDATE users SET status = 'SUSPENDED' WHERE id = $1`, [user.id]);

    const res = await me(tokens.accessToken);

    expect(res.status).toBe(403);
    expect(res.body.meta.code).toBe('ACCOUNT_NOT_ACTIVE');
  });

  test('an admin cannot deactivate their own account', async () => {
    const { user, tokens } = await signedInUser();
    await db.query(`UPDATE users SET role = 'ADMIN' WHERE id = $1`, [user.id]);

    const res = await deactivate(tokens.accessToken);

    expect(res.status).toBe(403);
    expect(res.body.meta.code).toBe('ADMIN_CANNOT_DEACTIVATE');
  });
});
