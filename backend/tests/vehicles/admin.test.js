// Admin API tests: SCRUM-55 (approve/reject) and SCRUM-56 (admin activate/deactivate)
const f = require('./fixtures');
const { api, auth, db } = f;

beforeAll(f.start);
beforeEach(f.reset);
afterAll(f.stop);

async function pendingVehicle(driverToken, overrides) {
  const v = await f.createVehicle(driverToken, overrides);
  await f.uploadRequired(driverToken, v.id);
  await api().post(`/api/v1/vehicles/${v.id}/verification/submit`).set(auth(driverToken)).expect(200);
  return v;
}

describe('GET /api/v1/admin/vehicles', () => {
  test('403 for non-admins', async () => {
    const { accessToken } = await f.driver();
    await api().get('/api/v1/admin/vehicles').set(auth(accessToken)).expect(403);
  });

  test('filters by status, searches by plate and paginates', async () => {
    const d = await f.driver();
    const a = await f.admin();
    await pendingVehicle(d.accessToken, { plateNumber: 'CAB-1001' });
    await f.createVehicle(d.accessToken, { plateNumber: 'CAB-1002' });

    const pending = await api()
      .get('/api/v1/admin/vehicles?verificationStatus=PENDING')
      .set(auth(a.accessToken))
      .expect(200);
    expect(pending.body.data).toHaveLength(1);
    expect(pending.body.data[0].owner.phone).toBeTruthy();
    expect(pending.body.meta).toMatchObject({ page: 1, total: 1 });

    const search = await api().get('/api/v1/admin/vehicles?q=CAB-1002').set(auth(a.accessToken)).expect(200);
    expect(search.body.data.map((v) => v.plateNumber)).toEqual(['CAB-1002']);

    const paged = await api().get('/api/v1/admin/vehicles?limit=1&page=2').set(auth(a.accessToken)).expect(200);
    expect(paged.body.data).toHaveLength(1);
    expect(paged.body.meta.total).toBe(2);
  });

  test('detail includes owner and documents', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await pendingVehicle(d.accessToken);
    const res = await api().get(`/api/v1/admin/vehicles/${v.id}`).set(auth(a.accessToken)).expect(200);
    expect(res.body.data.owner.fullName).toBeTruthy();
    expect(res.body.data.documents).toHaveLength(4);
  });
});

describe('PATCH /api/v1/admin/vehicles/:id/verification', () => {
  test('approve marks documents ACCEPTED and vehicle APPROVED', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await pendingVehicle(d.accessToken);
    const res = await api()
      .patch(`/api/v1/admin/vehicles/${v.id}/verification`)
      .set(auth(a.accessToken))
      .send({ decision: 'APPROVE' })
      .expect(200);
    expect(res.body.data.verificationStatus).toBe('APPROVED');
    expect(res.body.data.verifiedBy).toBe(a.user.id);
    expect(res.body.data.documents.every((doc) => doc.status === 'ACCEPTED')).toBe(true);
  });

  test('reject needs a reason; driver sees it and can fix + resubmit', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await pendingVehicle(d.accessToken);

    await api()
      .patch(`/api/v1/admin/vehicles/${v.id}/verification`)
      .set(auth(a.accessToken))
      .send({ decision: 'REJECT' })
      .expect(422);

    const docs = await api().get(`/api/v1/admin/vehicles/${v.id}`).set(auth(a.accessToken));
    const insurance = docs.body.data.documents.find((doc) => doc.docType === 'INSURANCE');

    await api()
      .patch(`/api/v1/admin/vehicles/${v.id}/verification`)
      .set(auth(a.accessToken))
      .send({ decision: 'REJECT', reason: 'Insurance expired', documents: [{ id: insurance.id, status: 'REJECTED' }] })
      .expect(200);

    const status = await api().get(`/api/v1/vehicles/${v.id}/verification`).set(auth(d.accessToken)).expect(200);
    expect(status.body.data).toMatchObject({
      status: 'REJECTED',
      rejectionReason: 'Insurance expired',
      missingDocuments: ['INSURANCE'],
    });

    await f.upload(d.accessToken, v.id, 'INSURANCE').expect(201);
    await api().post(`/api/v1/vehicles/${v.id}/verification/submit`).set(auth(d.accessToken)).expect(200);
  });

  test('409 INVALID_STATE when the vehicle is not PENDING', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await f.createVehicle(d.accessToken);
    const res = await api()
      .patch(`/api/v1/admin/vehicles/${v.id}/verification`)
      .set(auth(a.accessToken))
      .send({ decision: 'APPROVE' })
      .expect(409);
    expect(res.body.meta.code).toBe('INVALID_STATE');
  });

  test('cannot approve when a required document was rejected in the same request', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await pendingVehicle(d.accessToken);
    const detail = await api().get(`/api/v1/admin/vehicles/${v.id}`).set(auth(a.accessToken));
    const photo = detail.body.data.documents.find((doc) => doc.docType === 'PHOTO_FRONT');
    await api()
      .patch(`/api/v1/admin/vehicles/${v.id}/verification`)
      .set(auth(a.accessToken))
      .send({ decision: 'APPROVE', documents: [{ id: photo.id, status: 'REJECTED' }] })
      .expect(422);
    // transaction rolled back -> still PENDING, photo not rejected
    const after = await api().get(`/api/v1/admin/vehicles/${v.id}`).set(auth(a.accessToken));
    expect(after.body.data.verificationStatus).toBe('PENDING');
    expect(after.body.data.documents.find((doc) => doc.docType === 'PHOTO_FRONT').status).toBe('UPLOADED');
  });

  test('writes an audit log', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await pendingVehicle(d.accessToken);
    await api().patch(`/api/v1/admin/vehicles/${v.id}/verification`).set(auth(a.accessToken)).send({ decision: 'APPROVE' });
    const { rows } = await db.query(
      "SELECT 1 FROM audit_logs WHERE entity_type = 'VEHICLE' AND entity_id = $1 AND action = 'VEHICLE_APPROVED'",
      [v.id],
    );
    expect(rows).toHaveLength(1);
  });
});

describe('PATCH /api/v1/admin/vehicles/:id/status', () => {
  test('deactivate needs a reason; owner cannot re-activate after admin deactivation', async () => {
    const d = await f.driver();
    const a = await f.admin();
    const v = await f.createVehicle(d.accessToken);

    await api().patch(`/api/v1/admin/vehicles/${v.id}/status`).set(auth(a.accessToken)).send({ isActive: false }).expect(422);
    const off = await api()
      .patch(`/api/v1/admin/vehicles/${v.id}/status`)
      .set(auth(a.accessToken))
      .send({ isActive: false, reason: 'Fake documents' })
      .expect(200);
    expect(off.body.data.isActive).toBe(false);

    await api().patch(`/api/v1/vehicles/${v.id}/active`).set(auth(d.accessToken)).send({ isActive: true }).expect(403);

    await api().patch(`/api/v1/admin/vehicles/${v.id}/status`).set(auth(a.accessToken)).send({ isActive: true }).expect(200);
    await api().patch(`/api/v1/vehicles/${v.id}/active`).set(auth(d.accessToken)).send({ isActive: false }).expect(200);
  });

  describe('with the agreed trips table', () => {
    // The trip module is not merged yet, so this creates just the columns the rule reads.
    beforeAll(() =>
      db.exec(`
        CREATE TABLE trips (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          vehicle_id UUID NOT NULL,
          status TEXT NOT NULL
        )
      `),
    );
    afterAll(() => db.exec('DROP TABLE trips'));

    test('409 when the vehicle has a SCHEDULED trip', async () => {
      const d = await f.driver();
      const a = await f.admin();
      const v = await f.approvedVehicle(d.accessToken, a.accessToken);
      await db.query("INSERT INTO trips (vehicle_id, status) VALUES ($1, 'SCHEDULED')", [v.id]);

      const res = await api().patch(`/api/v1/vehicles/${v.id}/active`).set(auth(d.accessToken)).send({ isActive: false }).expect(409);
      expect(res.body.meta.code).toBe('INVALID_STATE');
      await api()
        .patch(`/api/v1/admin/vehicles/${v.id}/status`)
        .set(auth(a.accessToken))
        .send({ isActive: false, reason: 'test' })
        .expect(409);
    });

    test('a COMPLETED trip does not block deactivation', async () => {
      const d = await f.driver();
      const v = await f.createVehicle(d.accessToken);
      await db.query("INSERT INTO trips (vehicle_id, status) VALUES ($1, 'COMPLETED')", [v.id]);
      await api().patch(`/api/v1/vehicles/${v.id}/active`).set(auth(d.accessToken)).send({ isActive: false }).expect(200);
    });
  });
});
