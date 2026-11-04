const request = require('supertest');
const createApp = require('../../src/app');

const app = createApp();

const PASSWORD = 'Str0ngPass';

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

/** Registers a user and signs them in. Returns { data, user, tokens }. */
async function signedInUser(overrides = {}) {
  const data = newUserData(overrides);
  const registered = await post('/auth/register', data);
  expect(registered.status).toBe(201);

  const login = await post('/auth/login', { phone: data.phone, password: data.password });
  expect(login.status).toBe(200);
  return { data, user: login.body.data.user, tokens: login.body.data.tokens };
}

module.exports = { app, PASSWORD, newUserData, post, signedInUser };
