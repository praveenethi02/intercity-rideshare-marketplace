const db = require('../src/db');
const { PASSWORD, smsSend, newUserData, post, lastOtp, signedInUser } = require('./helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('./helpers/test-db');

beforeAll(startTestDb);
beforeEach(async () => {
  await resetTestDb();
  smsSend.mockClear();
});
afterAll(stopTestDb);

const NEW_PASSWORD = 'N3wPassword';

const wrongCode = (code) => (code === '000000' ? '000001' : '000000');

/** Moves all stored codes into the past, to get past the resend cooldown. */
const age = (interval) =>
  db.query(`UPDATE otp_codes SET created_at = created_at - interval '${interval}'`);

describe('phone verification', () => {
  test('a new account is pending, receives a code and cannot log in yet', async () => {
    const data = newUserData();
    const res = await post('/auth/register', data);

    expect(res.body.data.user.status).toBe('PENDING_VERIFICATION');
    expect(res.body.data).not.toHaveProperty('tokens');
    expect(lastOtp(data.phone)).toMatch(/^\d{6}$/);

    const login = await post('/auth/login', { phone: data.phone, password: data.password });
    expect(login.status).toBe(403);
    expect(login.body.meta.code).toBe('PHONE_NOT_VERIFIED');
  });

  test('the code is never stored in plain text or returned by the API', async () => {
    const data = newUserData();
    const res = await post('/auth/register', data);
    const code = lastOtp(data.phone);

    expect(JSON.stringify(res.body)).not.toContain(code);
    const { rows } = await db.query('SELECT code_hash FROM otp_codes');
    expect(rows[0].code_hash).not.toContain(code);
  });

  test('the correct code activates the account and signs the user in', async () => {
    const { data, user, tokens } = await signedInUser();

    expect(user.status).toBe('ACTIVE');
    expect(user.phoneVerifiedAt).not.toBeNull();
    expect(tokens.accessToken).toEqual(expect.any(String));

    const login = await post('/auth/login', { phone: data.phone, password: data.password });
    expect(login.status).toBe(200);
  });

  test('a code only works once', async () => {
    const data = newUserData();
    await post('/auth/register', data);
    const otp = lastOtp(data.phone);

    expect((await post('/auth/otp/verify', { phone: data.phone, otp })).status).toBe(200);
    expect((await post('/auth/otp/verify', { phone: data.phone, otp })).status).toBe(400);
  });

  test('a wrong code is rejected', async () => {
    const data = newUserData();
    await post('/auth/register', data);

    const res = await post('/auth/otp/verify', {
      phone: data.phone,
      otp: wrongCode(lastOtp(data.phone)),
    });

    expect(res.status).toBe(400);
    expect(res.body.meta.code).toBe('OTP_INVALID_OR_EXPIRED');
  });

  test('an expired code is rejected', async () => {
    const data = newUserData();
    await post('/auth/register', data);
    await db.query(`UPDATE otp_codes SET expires_at = now() - interval '1 second'`);

    const res = await post('/auth/otp/verify', { phone: data.phone, otp: lastOtp(data.phone) });

    expect(res.status).toBe(400);
  });

  test('too many wrong codes cancel the code, even if the next guess is right', async () => {
    const data = newUserData();
    await post('/auth/register', data);
    const otp = lastOtp(data.phone);

    for (let i = 0; i < 5; i += 1) {
      const res = await post('/auth/otp/verify', { phone: data.phone, otp: wrongCode(otp) });
      expect(res.status).toBe(400);
    }

    const blocked = await post('/auth/otp/verify', { phone: data.phone, otp });
    expect(blocked.status).toBe(429);
    expect(blocked.body.meta.code).toBe('OTP_TOO_MANY_ATTEMPTS');

    expect((await post('/auth/otp/verify', { phone: data.phone, otp })).status).toBe(400);
  });

  test('resend respects the cooldown and cancels the old code', async () => {
    const data = newUserData();
    await post('/auth/register', data);
    const first = lastOtp(data.phone);

    const tooSoon = await post('/auth/otp/resend', { phone: data.phone });
    expect(tooSoon.status).toBe(429);
    expect(tooSoon.body.meta.code).toBe('OTP_COOLDOWN');

    await age('2 minutes');
    expect((await post('/auth/otp/resend', { phone: data.phone })).status).toBe(200);
    expect(smsSend).toHaveBeenCalledTimes(2);

    const second = lastOtp(data.phone);
    if (first !== second) {
      const old = await post('/auth/otp/verify', { phone: data.phone, otp: first });
      expect(old.status).toBe(400);
    }
    expect((await post('/auth/otp/verify', { phone: data.phone, otp: second })).status).toBe(200);
  });

  test('stops sending after the hourly limit', async () => {
    const data = newUserData();
    await post('/auth/register', data);

    for (let i = 0; i < 4; i += 1) {
      await age('2 minutes');
      expect((await post('/auth/otp/resend', { phone: data.phone })).status).toBe(200);
    }

    await age('2 minutes');
    const res = await post('/auth/otp/resend', { phone: data.phone });
    expect(res.status).toBe(429);
    expect(res.body.meta.code).toBe('OTP_LIMIT_REACHED');
  });

  test('resend does not reveal whether a phone number is registered', async () => {
    const { data } = await signedInUser();
    smsSend.mockClear();

    const verified = await post('/auth/otp/resend', { phone: data.phone });
    const unknown = await post('/auth/otp/resend', { phone: '0779999999' });

    expect(verified.status).toBe(200);
    expect(verified.body).toEqual(unknown.body);
    expect(smsSend).not.toHaveBeenCalled();
  });

  test('an unverified number can be registered again by its real owner', async () => {
    const stranger = newUserData({ phone: '0771234567', password: 'Str4ngerPass' });
    await post('/auth/register', stranger);
    await age('2 minutes');

    const owner = newUserData({ phone: '0771234567', fullName: 'Real Owner' });
    const res = await post('/auth/register', owner);
    expect(res.status).toBe(201);
    expect(res.body.data.user.fullName).toBe('Real Owner');

    await post('/auth/otp/verify', { phone: owner.phone, otp: lastOtp(owner.phone) });

    const strangerLogin = await post('/auth/login', {
      phone: owner.phone,
      password: stranger.password,
    });
    expect(strangerLogin.status).toBe(401);
    expect(
      (await post('/auth/login', { phone: owner.phone, password: owner.password })).status,
    ).toBe(200);
  });

  test('a failed SMS returns 502 and leaves no usable code', async () => {
    const consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
    smsSend.mockRejectedValueOnce(new Error('gateway down'));
    const data = newUserData();

    const res = await post('/auth/register', data);

    expect(res.status).toBe(502);
    const { rows } = await db.query('SELECT count(*)::int AS n FROM otp_codes WHERE consumed_at IS NULL');
    expect(rows[0].n).toBe(0);
    consoleError.mockRestore();
  });
});

describe('forgot and reset password', () => {
  async function requestReset(phone) {
    const res = await post('/auth/password/forgot', { phone });
    expect(res.status).toBe(200);
    return lastOtp(phone);
  }

  test('resets the password and signs out every device', async () => {
    const { data, tokens } = await signedInUser();
    const otp = await requestReset(data.phone);

    const res = await post('/auth/password/reset', {
      phone: data.phone,
      otp,
      newPassword: NEW_PASSWORD,
    });
    expect(res.status).toBe(200);

    expect((await post('/auth/logout', {}, tokens.accessToken)).status).toBe(401);
    expect(
      (await post('/auth/login', { phone: data.phone, password: PASSWORD })).status,
    ).toBe(401);
    expect(
      (await post('/auth/login', { phone: data.phone, password: NEW_PASSWORD })).status,
    ).toBe(200);
  });

  test('does not reveal whether a phone number is registered', async () => {
    const { data } = await signedInUser();

    const known = await post('/auth/password/forgot', { phone: data.phone });
    const unknown = await post('/auth/password/forgot', { phone: '0779999999' });

    expect(known.status).toBe(200);
    expect(known.body).toEqual(unknown.body);
    expect(smsSend).not.toHaveBeenCalledWith('+94779999999', expect.anything());
  });

  test('a registration code cannot be used to reset a password', async () => {
    const data = newUserData();
    await post('/auth/register', data);
    const registrationOtp = lastOtp(data.phone);
    await post('/auth/otp/verify', { phone: data.phone, otp: registrationOtp });

    const res = await post('/auth/password/reset', {
      phone: data.phone,
      otp: registrationOtp,
      newPassword: NEW_PASSWORD,
    });
    expect(res.status).toBe(400);
  });

  test('another user\'s code does not work', async () => {
    const first = await signedInUser();
    const second = await signedInUser();
    const otp = await requestReset(first.data.phone);
    await requestReset(second.data.phone);

    const res = await post('/auth/password/reset', {
      phone: second.data.phone,
      otp,
      newPassword: NEW_PASSWORD,
    });

    // A random match with the second user's own code would be a 1 in a million flake.
    if (otp !== lastOtp(second.data.phone)) {
      expect(res.status).toBe(400);
    }
  });

  test('the new password must meet the password rules', async () => {
    const { data } = await signedInUser();
    const otp = await requestReset(data.phone);

    const res = await post('/auth/password/reset', {
      phone: data.phone,
      otp,
      newPassword: 'weak',
    });

    expect(res.status).toBe(422);
  });
});

describe('POST /auth/password/change', () => {
  test('changes the password, keeps this device and signs out the others', async () => {
    const { data, tokens: current } = await signedInUser();
    const other = await post('/auth/login', { phone: data.phone, password: PASSWORD });

    const res = await post(
      '/auth/password/change',
      { currentPassword: PASSWORD, newPassword: NEW_PASSWORD },
      current.accessToken,
    );
    expect(res.status).toBe(200);

    expect((await post('/auth/logout', {}, other.body.data.tokens.accessToken)).status).toBe(401);
    expect((await post('/auth/logout', {}, current.accessToken)).status).toBe(200);
    expect(
      (await post('/auth/login', { phone: data.phone, password: NEW_PASSWORD })).status,
    ).toBe(200);
  });

  test('requires the correct current password', async () => {
    const { tokens } = await signedInUser();

    const res = await post(
      '/auth/password/change',
      { currentPassword: 'Wr0ngPass', newPassword: NEW_PASSWORD },
      tokens.accessToken,
    );

    expect(res.status).toBe(400);
    expect(res.body.meta.code).toBe('INCORRECT_PASSWORD');
  });

  test('the new password must be different', async () => {
    const { tokens } = await signedInUser();

    const res = await post(
      '/auth/password/change',
      { currentPassword: PASSWORD, newPassword: PASSWORD },
      tokens.accessToken,
    );

    expect(res.status).toBe(422);
  });

  test('requires being signed in', async () => {
    const res = await post('/auth/password/change', {
      currentPassword: PASSWORD,
      newPassword: NEW_PASSWORD,
    });

    expect(res.status).toBe(401);
  });
});
