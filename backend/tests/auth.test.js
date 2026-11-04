const jwt = require('jsonwebtoken');
const request = require('supertest');
const { app, newUserData, post, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(resetTestDb);
afterAll(stopTestDb);

const logoutRequest = (token) => post('/auth/logout', {}, token);

describe('POST /auth/register', () => {
  test('creates a user, normalises the phone and hides the password', async () => {
    const data = newUserData({ phone: '0771234567', email: 'Test@Example.com' });
    const res = await post('/auth/register', data);

    expect(res.status).toBe(201);
    expect(res.body.data.user).toMatchObject({
      phone: '+94771234567',
      email: 'test@example.com',
      role: 'PASSENGER',
    });
    expect(JSON.stringify(res.body)).not.toContain(data.password);
    expect(JSON.stringify(res.body)).not.toContain('password');
  });

  test.each(['PASSENGER', 'DRIVER', 'CARGO_CUSTOMER'])('allows role %s', async (role) => {
    const res = await post('/auth/register', newUserData({ role }));

    expect(res.status).toBe(201);
    expect(res.body.data.user.role).toBe(role);
  });

  test('cannot self-register as ADMIN', async () => {
    const res = await post('/auth/register', newUserData({ role: 'ADMIN' }));

    expect(res.status).toBe(422);
    expect(res.body.meta.details[0].field).toBe('body.role');
  });

  test('rejects extra fields such as status', async () => {
    const res = await post('/auth/register', newUserData({ status: 'ACTIVE' }));

    expect(res.status).toBe(422);
  });

  test.each([
    ['too short', 'Ab1'],
    ['no number', 'OnlyLetters'],
    ['no letter', '1234567890'],
    ['over 72 bytes', `A1${'x'.repeat(71)}`],
  ])('rejects a weak password: %s', async (_name, password) => {
    const res = await post('/auth/register', newUserData({ password }));

    expect(res.status).toBe(422);
  });

  test('rejects an invalid phone number', async () => {
    const res = await post('/auth/register', newUserData({ phone: '12345' }));

    expect(res.status).toBe(422);
    expect(res.body.meta.details[0].field).toBe('body.phone');
  });

  test('rejects a phone number that is already registered, in any format', async () => {
    await post('/auth/register', newUserData({ phone: '0771234567' }));
    const res = await post('/auth/register', newUserData({ phone: '+94771234567' }));

    expect(res.status).toBe(409);
    expect(res.body.meta.code).toBe('PHONE_ALREADY_REGISTERED');
  });

  test('rejects an email that is already used', async () => {
    await signedInUser({ email: 'same@example.com' });
    const res = await post('/auth/register', newUserData({ email: 'SAME@example.com' }));

    expect(res.status).toBe(409);
  });
});

describe('POST /auth/login', () => {
  test('returns the user and tokens', async () => {
    const { data, user, tokens } = await signedInUser();

    expect(user.phone).toBe(`+94${data.phone.slice(1)}`);
    expect(tokens).toMatchObject({ tokenType: 'Bearer', expiresIn: 900 });
    expect(tokens.accessToken).toEqual(expect.any(String));
    expect(tokens.refreshToken).toEqual(expect.any(String));
  });

  test('gives the same error for a wrong password and an unknown phone', async () => {
    const { data } = await signedInUser();

    const wrongPassword = await post('/auth/login', { phone: data.phone, password: 'Wr0ngPass' });
    const unknownPhone = await post('/auth/login', { phone: '0779999999', password: 'Wr0ngPass' });

    expect(wrongPassword.status).toBe(401);
    expect(unknownPhone.status).toBe(401);
    expect(wrongPassword.body).toEqual(unknownPhone.body);
  });
});

describe('access tokens', () => {
  const protectedRoute = (headerValue) => {
    const req = request(app).post('/api/v1/auth/logout');
    return headerValue ? req.set('Authorization', headerValue) : req;
  };

  test('a missing or malformed token gets 401', async () => {
    expect((await protectedRoute()).status).toBe(401);
    expect((await protectedRoute('Bearer not-a-token')).status).toBe(401);
    expect((await protectedRoute('Basic abc')).status).toBe(401);
  });

  test('a token signed with another secret gets 401', async () => {
    const { user, tokens } = await signedInUser();
    const { sid } = jwt.decode(tokens.accessToken);
    const forged = jwt.sign({ sid }, 'another-secret', {
      subject: user.id,
      issuer: 'intercity-rideshare',
    });

    expect((await protectedRoute(`Bearer ${forged}`)).status).toBe(401);
  });

  test('an unsigned (alg: none) token gets 401', async () => {
    const { user, tokens } = await signedInUser();
    const { sid } = jwt.decode(tokens.accessToken);
    const unsigned = jwt.sign({ sid }, '', {
      algorithm: 'none',
      subject: user.id,
      issuer: 'intercity-rideshare',
    });

    expect((await protectedRoute(`Bearer ${unsigned}`)).status).toBe(401);
  });
});

describe('POST /auth/logout', () => {
  test('makes the access and refresh tokens stop working immediately', async () => {
    const { tokens } = await signedInUser();

    expect((await logoutRequest(tokens.accessToken)).status).toBe(200);

    expect((await logoutRequest(tokens.accessToken)).status).toBe(401);
    const refreshed = await post('/auth/refresh', { refreshToken: tokens.refreshToken });
    expect(refreshed.status).toBe(401);
  });

  test('only signs out the current device', async () => {
    const { data, tokens: first } = await signedInUser();
    const second = await post('/auth/login', { phone: data.phone, password: data.password });

    await logoutRequest(first.accessToken);

    expect((await logoutRequest(second.body.data.tokens.accessToken)).status).toBe(200);
  });

  test('logout-all signs out every device', async () => {
    const { data, tokens: first } = await signedInUser();
    const second = await post('/auth/login', { phone: data.phone, password: data.password });

    expect((await post('/auth/logout-all', {}, first.accessToken)).status).toBe(200);

    expect((await logoutRequest(first.accessToken)).status).toBe(401);
    expect((await logoutRequest(second.body.data.tokens.accessToken)).status).toBe(401);
  });
});

describe('POST /auth/refresh', () => {
  test('issues working tokens and replaces the refresh token', async () => {
    const { tokens } = await signedInUser();

    const res = await post('/auth/refresh', { refreshToken: tokens.refreshToken });

    expect(res.status).toBe(200);
    expect(res.body.data.tokens.refreshToken).not.toBe(tokens.refreshToken);
    expect((await logoutRequest(res.body.data.tokens.accessToken)).status).toBe(200);
  });

  test('reusing an old refresh token ends the session', async () => {
    const { tokens } = await signedInUser();
    const rotated = await post('/auth/refresh', { refreshToken: tokens.refreshToken });

    const reuse = await post('/auth/refresh', { refreshToken: tokens.refreshToken });
    expect(reuse.status).toBe(401);

    const newest = await post('/auth/refresh', {
      refreshToken: rotated.body.data.tokens.refreshToken,
    });
    expect(newest.status).toBe(401);
  });

  test.each(['garbage', 'not-a-uuid.abc', '00000000-0000-0000-0000-000000000000.abc'])(
    'rejects %s without a server error',
    async (refreshToken) => {
      const res = await post('/auth/refresh', { refreshToken });

      expect(res.status).toBe(401);
      expect(res.body.meta.code).toBe('INVALID_REFRESH_TOKEN');
    },
  );
});
