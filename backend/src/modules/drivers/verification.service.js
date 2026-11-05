const db = require('../../db');
const ApiError = require('../../utils/ApiError');
const driverRepository = require('./driver.repository');
const { toDocument, toProfile } = require('./driver.service');
const { VERIFICATION_STATUS } = require('./driver.constants');
const verificationRepository = require('./verification.repository');

const toVerification = (request, documents) => ({
  id: request.id,
  type: request.type,
  subjectId: request.subject_id,
  status: request.status,
  reason: request.reason,
  documents,
  submittedAt: request.submitted_at,
  decidedAt: request.decided_at,
  decidedBy: request.decided_by,
});

async function documentsByDriver(userIds) {
  const byDriver = new Map();
  for (const row of await driverRepository.listDocumentsForDrivers(userIds)) {
    const documents = byDriver.get(row.driver_user_id) ?? [];
    documents.push(toDocument(row));
    byDriver.set(row.driver_user_id, documents);
  }
  return byDriver;
}

// SCRUM-43
async function listQueue(query) {
  const { requests, total } = await verificationRepository.search(query);
  const driverIds = requests.filter((r) => r.type === 'DRIVER').map((r) => r.subject_id);
  const documents = await documentsByDriver(driverIds);
  return {
    total,
    verifications: requests.map((r) => toVerification(r, documents.get(r.subject_id) ?? [])),
  };
}

// SCRUM-43
async function decide(admin, requestId, { decision, reason }) {
  const storedReason = decision === VERIFICATION_STATUS.REJECTED ? reason : null;

  const request = await db.transaction(async (tx) => {
    const found = await verificationRepository.lock(requestId, tx);
    if (!found) throw new ApiError(404, 'VERIFICATION_NOT_FOUND', 'Verification request not found');
    if (found.status !== VERIFICATION_STATUS.PENDING) {
      throw new ApiError(409, 'INVALID_STATUS', `This request was already ${found.status.toLowerCase()}`);
    }
    if (found.type !== 'DRIVER') {
      throw new ApiError(409, 'INVALID_STATUS', 'Vehicle verification is not available yet');
    }

    const updated = await verificationRepository.decide(
      requestId,
      { status: decision, reason: storedReason, adminId: admin.id },
      tx,
    );
    await driverRepository.setVerification(
      found.subject_id,
      { status: decision, reason: storedReason, adminId: admin.id },
      tx,
    );
    await driverRepository.writeAudit(
      {
        actorId: admin.id,
        action: `VERIFICATION_${decision}`,
        entityType: 'VERIFICATION',
        entityId: requestId,
        details: { reason: storedReason },
      },
      tx,
    );
    return updated;
  });

  const documents = await documentsByDriver([request.subject_id]);
  return toVerification(request, documents.get(request.subject_id) ?? []);
}

// SCRUM-47
async function setAccountStatus(admin, driverUserId, { status, reason }) {
  const driver = await db.transaction(async (tx) => {
    const updated = await driverRepository.setAccountStatus(driverUserId, status, tx);
    if (!updated) throw new ApiError(404, 'DRIVER_NOT_FOUND', 'Driver not found');
    await driverRepository.writeAudit(
      {
        actorId: admin.id,
        action: `DRIVER_ACCOUNT_${status}`,
        entityType: 'DRIVER',
        entityId: driverUserId,
        details: { reason: reason ?? null },
      },
      tx,
    );
    return updated;
  });
  return toProfile(driver);
}

module.exports = { listQueue, decide, setAccountStatus };
