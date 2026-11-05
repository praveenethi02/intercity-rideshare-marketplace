// Driver-side API tests: SCRUM-48 -> SCRUM-54, SCRUM-56 (owner)
const f = require('./fixtures');
const fs = require('node:fs');
const { api, auth } = f;

beforeAll(f.start);
beforeEach(f.reset);
afterAll(f.stop);

describe('GET /api/v1/vehicles/types', () => {
  test('returns type config for the dropdown', async () => {
    const { accessToken } = await f.driver();
    const res = await api().get('/api/v1/vehicles/types').set(auth(accessToken)).expect(200);
    const car = res.body.data.find((t) => t.type === 'CAR');
    expect(car).toMatchObject({ minSeats: 2, maxSeats: 5, maxCargoKg: 100 });
  });
});

describe('POST /api/v1/vehicles (create)', () => {
  test('creates a vehicle with a normalised plate and NOT_SUBMITTED status', async () => {
    const { accessToken, user } = await f.driver();
    const res = await api()
      .post('/api/v1/vehicles')
      .set(auth(accessToken))
      .send(f.carPayload({ plateNumber: 'wp  cab 7777' }))
      .expect(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toMatchObject({
      driverUserId: user.id,
      plateNumber: 'WP CAB-7777',
      totalSeats: 5,
      passengerSeats: 4,
      verificationStatus: 'NOT_SUBMITTED',
      isActive: true,
    });
  });

  test('passengerSeats defaults to totalSeats - 1', async () => {
    const { accessToken } = await f.driver();
    const payload = f.carPayload({ totalSeats: 4 });
    delete payload.passengerSeats;
    const res = await api().post('/api/v1/vehicles').set(auth(accessToken)).send(payload).expect(201);
    expect(res.body.data.passengerSeats).toBe(3);
  });

  test('401 without token', async () => {
    await api().post('/api/v1/vehicles').send(f.carPayload()).expect(401);
  });

  test('403 for a user without DRIVER role', async () => {
    const { accessToken } = await f.passenger();
    const res = await api().post('/api/v1/vehicles').set(auth(accessToken)).send(f.carPayload()).expect(403);
    expect(res.body.meta.code).toBe('FORBIDDEN');
  });

  test('422 when seats are outside the type limits', async () => {
    const { accessToken } = await f.driver();
    const res = await api()
      .post('/api/v1/vehicles')
      .set(auth(accessToken))
      .send(f.carPayload({ totalSeats: 9, passengerSeats: 8 }))
      .expect(422);
    expect(res.body.meta.code).toBe('VALIDATION_ERROR');
  });

  test('422 when passengerSeats >= totalSeats', async () => {
    const { accessToken } = await f.driver();
    await api()
      .post('/api/v1/vehicles')
      .set(auth(accessToken))
      .send(f.carPayload({ totalSeats: 5, passengerSeats: 5 }))
      .expect(422);
  });

  test('422 when cargo is above the type limit', async () => {
    const { accessToken } = await f.driver();
    await api()
      .post('/api/v1/vehicles')
      .set(auth(accessToken))
      .send(f.carPayload({ cargoCapacityKg: 500 }))
      .expect(422);
  });

  test('422 for an invalid plate / year', async () => {
    const { accessToken } = await f.driver();
    await api().post('/api/v1/vehicles').set(auth(accessToken)).send(f.carPayload({ plateNumber: 'HELLO' })).expect(422);
    await api().post('/api/v1/vehicles').set(auth(accessToken)).send(f.carPayload({ year: 1985 })).expect(422);
  });

  test('409 for a duplicate plate (even written differently)', async () => {
    const a = await f.driver();
    const b = await f.driver();
    await f.createVehicle(a.accessToken, { plateNumber: 'CAB-5555' });
    const res = await api()
      .post('/api/v1/vehicles')
      .set(auth(b.accessToken))
      .send(f.carPayload({ plateNumber: 'cab 5555' }))
      .expect(409);
    expect(res.body.meta.code).toBe('CONFLICT');
  });

  test('409 for the 4th vehicle of one driver', async () => {
    const { accessToken } = await f.driver();
    await f.createVehicle(accessToken);
    await f.createVehicle(accessToken);
    await f.createVehicle(accessToken);
    await api().post('/api/v1/vehicles').set(auth(accessToken)).send(f.carPayload()).expect(409);
  });
});

describe('GET /mine, GET /:id, PATCH /:id', () => {
  test('lists only my vehicles', async () => {
    const a = await f.driver();
    const b = await f.driver();
    await f.createVehicle(a.accessToken);
    await f.createVehicle(b.accessToken);
    const res = await api().get('/api/v1/vehicles/mine').set(auth(a.accessToken)).expect(200);
    expect(res.body.data).toHaveLength(1);
  });

  test('another driver cannot read or edit my vehicle', async () => {
    const a = await f.driver();
    const b = await f.driver();
    const v = await f.createVehicle(a.accessToken);
    const read = await api().get(`/api/v1/vehicles/${v.id}`).set(auth(b.accessToken));
    expect([403, 404]).toContain(read.status);
    const edit = await api().patch(`/api/v1/vehicles/${v.id}`).set(auth(b.accessToken)).send({ color: 'Red' });
    expect([403, 404]).toContain(edit.status);
  });

  test('admin can read any vehicle', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await f.createVehicle(d.accessToken);
    await api().get(`/api/v1/vehicles/${v.id}`).set(auth(a.accessToken)).expect(200);
  });

  test('422 for a non-uuid id', async () => {
    const { accessToken } = await f.driver();
    await api().get('/api/v1/vehicles/not-a-uuid').set(auth(accessToken)).expect(422);
  });

  test('edit validates the merged values against type limits', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken); // CAR 5 seats
    await api().patch(`/api/v1/vehicles/${v.id}`).set(auth(accessToken)).send({ vehicleType: 'BUS' }).expect(422);
  });

  test('editing seats of an APPROVED vehicle resets it to PENDING; colour does not', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await f.approvedVehicle(d.accessToken, a.accessToken);

    const colour = await api().patch(`/api/v1/vehicles/${v.id}`).set(auth(d.accessToken)).send({ color: 'Black' }).expect(200);
    expect(colour.body.data.verificationStatus).toBe('APPROVED');

    const seats = await api()
      .patch(`/api/v1/vehicles/${v.id}`)
      .set(auth(d.accessToken))
      .send({ passengerSeats: 3 })
      .expect(200);
    expect(seats.body.data.verificationStatus).toBe('PENDING');
    expect(seats.body.data.verifiedAt).toBeNull();
  });
});

describe('documents + verification (SCRUM-53/54)', () => {
  test('upload, re-upload replaces, list', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);
    const first = await f.upload(accessToken, v.id, 'INSURANCE').expect(201);
    const second = await f.upload(accessToken, v.id, 'INSURANCE').expect(201);
    expect(second.body.data.id).toBe(first.body.data.id); // same row, new file
    const list = await api().get(`/api/v1/vehicles/${v.id}/documents`).set(auth(accessToken)).expect(200);
    expect(list.body.data).toHaveLength(1);
  });

  test('422 for an unknown docType or a missing file', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);
    await f.upload(accessToken, v.id, 'SELFIE').expect(422);
    await api()
      .post(`/api/v1/vehicles/${v.id}/documents`)
      .set(auth(accessToken))
      .field('docType', 'INSURANCE')
      .expect(422);
  });

  test('fileUrl is a signed link that serves the file', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);
    const res = await f.upload(accessToken, v.id, 'INSURANCE').expect(201);
    const { pathname, search } = new URL(res.body.data.fileUrl);
    expect(pathname.endsWith('.pdf')).toBe(true);
    await api().get(`${pathname}${search}`).expect(200);
    await api().get(pathname).expect(403);
  });

  test('re-upload removes the old file from storage', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);
    const fileName = (res) => new URL(res.body.data.fileUrl).pathname.split('/').pop();
    const first = await f.upload(accessToken, v.id, 'INSURANCE').expect(201);
    const second = await f.upload(accessToken, v.id, 'INSURANCE').expect(201);
    const stored = fs.readdirSync(f.uploadDir);
    expect(stored).not.toContain(fileName(first));
    expect(stored).toContain(fileName(second));
  });

  test('400 when the content is not a JPG, PNG or PDF, whatever the file name says', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);
    const res = await f.upload(accessToken, v.id, 'INSURANCE', Buffer.from('not really a pdf')).expect(400);
    expect(res.body.meta.code).toBe('FILE_INVALID');
  });

  test('another driver cannot upload to my vehicle', async () => {
    const a = await f.driver();
    const b = await f.driver();
    const v = await f.createVehicle(a.accessToken);
    await f.upload(b.accessToken, v.id, 'INSURANCE').expect(404);
  });

  test('re-uploading a document on an APPROVED vehicle sends it back to PENDING', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await f.approvedVehicle(d.accessToken, a.accessToken);
    await f.upload(d.accessToken, v.id, 'INSURANCE').expect(201);
    const res = await api().get(`/api/v1/vehicles/${v.id}`).set(auth(d.accessToken)).expect(200);
    expect(res.body.data.verificationStatus).toBe('PENDING');
    expect(res.body.data.verifiedBy).toBeNull();
  });

  test('submit fails while documents are missing, then succeeds', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);

    const status = await api().get(`/api/v1/vehicles/${v.id}/verification`).set(auth(accessToken)).expect(200);
    expect(status.body.data.status).toBe('NOT_SUBMITTED');
    expect(status.body.data.missingDocuments).toEqual(f.REQUIRED);

    await f.upload(accessToken, v.id, 'REGISTRATION_CERT').expect(201);
    const missing = await api().post(`/api/v1/vehicles/${v.id}/verification/submit`).set(auth(accessToken)).expect(422);
    expect(missing.body.meta.details.map((d) => d.docType)).toEqual(['REVENUE_LICENSE', 'INSURANCE', 'PHOTO_FRONT']);

    await f.uploadRequired(accessToken, v.id);
    const ok = await api().post(`/api/v1/vehicles/${v.id}/verification/submit`).set(auth(accessToken)).expect(200);
    expect(ok.body.data).toMatchObject({ status: 'PENDING', missingDocuments: [] });

    // submitting again is not allowed
    const again = await api().post(`/api/v1/vehicles/${v.id}/verification/submit`).set(auth(accessToken)).expect(409);
    expect(again.body.meta.code).toBe('INVALID_STATE');
  });
});

describe('PATCH /:id/active (SCRUM-56 owner)', () => {
  test('owner can deactivate and activate', async () => {
    const { accessToken } = await f.driver();
    const v = await f.createVehicle(accessToken);
    const off = await api().patch(`/api/v1/vehicles/${v.id}/active`).set(auth(accessToken)).send({ isActive: false }).expect(200);
    expect(off.body.data.isActive).toBe(false);
    const on = await api().patch(`/api/v1/vehicles/${v.id}/active`).set(auth(accessToken)).send({ isActive: true }).expect(200);
    expect(on.body.data.isActive).toBe(true);
  });

  test('isVehicleUsable = owner + APPROVED + active', async () => {
    const { isVehicleUsable } = require('../../src/modules/vehicles/vehicle.service');
    const d = await f.driver();
    const other = await f.driver();
    const a = await f.admin();
    const pending = await f.createVehicle(d.accessToken);
    const approved = await f.approvedVehicle(d.accessToken, a.accessToken);

    expect(await isVehicleUsable(approved.id, d.user.id)).toBe(true);
    expect(await isVehicleUsable(approved.id, other.user.id)).toBe(false);
    expect(await isVehicleUsable(pending.id, d.user.id)).toBe(false);
    expect(await isVehicleUsable('nope', d.user.id)).toBe(false);

    await api().patch(`/api/v1/vehicles/${approved.id}/active`).set(auth(d.accessToken)).send({ isActive: false }).expect(200);
    expect(await isVehicleUsable(approved.id, d.user.id)).toBe(false);
  });
});
