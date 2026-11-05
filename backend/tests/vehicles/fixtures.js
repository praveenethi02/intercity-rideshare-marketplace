// Shared setup for the vehicle tests (not a test file itself).
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Must be set before the app loads its configuration.
const uploadDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rideshare-vehicle-uploads-'));
process.env.UPLOAD_DIR = uploadDir;

const request = require('supertest');
const db = require('../../src/db');
const seedAdmin = require('../../src/db/seed-admin');
const { app, post, signedInUser } = require('../helpers/api');
const { startTestDb, resetTestDb, stopTestDb } = require('../helpers/test-db');

const ADMIN = { ADMIN_NAME: 'System Admin', ADMIN_PHONE: '0770000001', ADMIN_PASSWORD: 'Adm1nPassword' };

const api = () => request(app);
const auth = (token) => ({ Authorization: `Bearer ${token}` });

async function stop() {
  await stopTestDb();
  fs.rmSync(uploadDir, { recursive: true, force: true });
}

async function userWithRole(role) {
  const { user, tokens } = await signedInUser({ role });
  return { user, accessToken: tokens.accessToken };
}

const driver = () => userWithRole('DRIVER');
const passenger = () => userWithRole('PASSENGER');

async function admin() {
  await seedAdmin(ADMIN);
  const res = await post('/auth/login', { phone: ADMIN.ADMIN_PHONE, password: ADMIN.ADMIN_PASSWORD });
  return { user: res.body.data.user, accessToken: res.body.data.tokens.accessToken };
}

let plateCounter = 1000;

function carPayload(overrides = {}) {
  plateCounter += 1;
  return {
    vehicleType: 'CAR',
    make: 'Toyota',
    model: 'Axio',
    year: 2016,
    color: 'White',
    plateNumber: `wp cab ${plateCounter}`,
    totalSeats: 5,
    passengerSeats: 4,
    cargoCapacityKg: 50,
    cargoVolumeL: 300,
    ...overrides,
  };
}

async function createVehicle(token, overrides) {
  const res = await api().post('/api/v1/vehicles').set(auth(token)).send(carPayload(overrides));
  if (res.status !== 201) throw new Error(`createVehicle failed: ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data;
}

const PDF = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF');
const REQUIRED = ['REGISTRATION_CERT', 'REVENUE_LICENSE', 'INSURANCE', 'PHOTO_FRONT'];

function upload(token, vehicleId, docType, file = PDF) {
  return api()
    .post(`/api/v1/vehicles/${vehicleId}/documents`)
    .set(auth(token))
    .field('docType', docType)
    .attach('file', file, { filename: `${docType}.pdf`, contentType: 'application/pdf' });
}

async function uploadRequired(token, vehicleId) {
  for (const docType of REQUIRED) {
    const res = await upload(token, vehicleId, docType);
    if (res.status !== 201) throw new Error(`upload ${docType} failed: ${res.status} ${JSON.stringify(res.body)}`);
  }
}

/** Creates a vehicle, uploads documents, submits and lets an admin approve it. */
async function approvedVehicle(driverToken, adminToken, overrides) {
  const vehicle = await createVehicle(driverToken, overrides);
  await uploadRequired(driverToken, vehicle.id);
  await api().post(`/api/v1/vehicles/${vehicle.id}/verification/submit`).set(auth(driverToken)).expect(200);
  await api()
    .patch(`/api/v1/admin/vehicles/${vehicle.id}/verification`)
    .set(auth(adminToken))
    .send({ decision: 'APPROVE' })
    .expect(200);
  return vehicle;
}

module.exports = {
  app,
  db,
  api,
  auth,
  uploadDir,
  start: startTestDb,
  reset: resetTestDb,
  stop,
  driver,
  passenger,
  admin,
  carPayload,
  createVehicle,
  upload,
  uploadRequired,
  approvedVehicle,
  REQUIRED,
};
