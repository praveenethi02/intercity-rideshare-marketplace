const request = require('supertest');
const createApp = require('../../src/app');
const sms = require('../../src/services/sms');
const { normalizePhone } = require('../../src/utils/phone');

const app = createApp();

const PASSWORD = 'Str0ngPass';

const smsSend = jest.spyOn(sms, 'send').mockResolvedValue();

let nextPhone = 10000000;

/** Valid registration data with a phone number no other test has used. */
function newUserData(overrides = {}) {
  nextPhone += 1;
  return {
    fullName: 'Test User',
    phone: `07${nextPhone}`,
    password: PASSWORD,
    role: 'PASSENGER',
    ...overrides,
  };
}

const post = (path, body, accessToken) => {
  const req = request(app).post(`/api/v1${path}`);
  if (accessToken) req.set('Authorization', `Bearer ${accessToken}`);
  return req.send(body);
};

const send = (method) => (path, accessToken, body) => {
  const req = request(app)[method](`/api/v1${path}`);
  if (accessToken) req.set('Authorization', `Bearer ${accessToken}`);
  return body === undefined ? req : req.send(body);
};

const get = send('get');
const patch = send('patch');
const put = send('put');

/** The code from the most recent SMS sent to a phone number. */
function lastOtp(phone) {
  const normalized = normalizePhone(phone);
  const call = smsSend.mock.calls.filter(([to]) => to === normalized).at(-1);
  if (!call) throw new Error(`No SMS was sent to ${normalized}`);
  return call[1].match(/\b\d{6}\b/)[0];
}

/** Registers a user, verifies their phone and signs them in. Returns { data, user, tokens }. */
async function signedInUser(overrides = {}) {
  const data = newUserData(overrides);
  const registered = await post('/auth/register', data);
  expect(registered.status).toBe(201);

  const verified = await post('/auth/otp/verify', { phone: data.phone, otp: lastOtp(data.phone) });
  expect(verified.status).toBe(200);
  return { data, user: verified.body.data.user, tokens: verified.body.data.tokens };
}

module.exports = {
  app,
  PASSWORD,
  smsSend,
  newUserData,
  post,
  get,
  patch,
  put,
  lastOtp,
  signedInUser,
};
