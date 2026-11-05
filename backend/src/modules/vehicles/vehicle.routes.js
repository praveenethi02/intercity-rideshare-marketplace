const { Router } = require('express');
const multer = require('multer');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const validate = require('../../middleware/validate');
const ApiError = require('../../utils/ApiError');
const respond = require('../../utils/respond');
const { ROLES } = require('../users/user.constants');
const schemas = require('./vehicle.schemas');
const vehicleService = require('./vehicle.service');
const { listVehicleTypes } = require('./vehicleTypes');

const MAX_FILE_BYTES = 5 * 1024 * 1024;

const parseUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_BYTES, files: 1 },
}).single('file');

function upload(req, res, next) {
  parseUpload(req, res, (error) => {
    if (error) return next(new ApiError(400, 'FILE_INVALID', 'File must be one file of at most 5 MB'));
    return next();
  });
}

const driverOnly = requireRole(ROLES.DRIVER);
const driverOrAdmin = requireRole(ROLES.DRIVER, ROLES.ADMIN);
const withId = validate({ params: schemas.idParams });

const router = Router();

router.use(authenticate);

// SCRUM-49. The fixed paths /types and /mine must come before /:id.
router.get('/types', (req, res) =>
  respond(res, { message: 'Vehicle types loaded', data: listVehicleTypes() }),
);

// SCRUM-48
router.get('/mine', driverOnly, async (req, res) => {
  const data = await vehicleService.listMyVehicles(req.user);
  return respond(res, { message: 'Vehicles loaded', data });
});

// SCRUM-48, SCRUM-50, SCRUM-51, SCRUM-52
router.post('/', driverOnly, validate({ body: schemas.createVehicleBody }), async (req, res) => {
  const data = await vehicleService.createVehicle(req.user, req.validated.body);
  return respond(res, { status: 201, message: 'Vehicle created', data });
});

router.get('/:id', driverOrAdmin, withId, async (req, res) => {
  const data = await vehicleService.getVehicle(req.user, req.validated.params.id);
  return respond(res, { message: 'Vehicle loaded', data });
});

router.patch(
  '/:id',
  driverOnly,
  validate({ params: schemas.idParams, body: schemas.updateVehicleBody }),
  async (req, res) => {
    const data = await vehicleService.updateVehicle(
      req.user,
      req.validated.params.id,
      req.validated.body,
    );
    return respond(res, { message: 'Vehicle updated', data });
  },
);

// SCRUM-56
router.patch(
  '/:id/active',
  driverOnly,
  validate({ params: schemas.idParams, body: schemas.setActiveBody }),
  async (req, res) => {
    const { isActive } = req.validated.body;
    const data = await vehicleService.setActive(req.user, req.validated.params.id, isActive);
    return respond(res, { message: isActive ? 'Vehicle activated' : 'Vehicle deactivated', data });
  },
);

// SCRUM-53
router.get('/:id/documents', driverOrAdmin, withId, async (req, res) => {
  const data = await vehicleService.listDocuments(req.user, req.validated.params.id);
  return respond(res, { message: 'Vehicle documents loaded', data });
});

// The id is checked before the upload is read, and each validate() call replaces req.validated,
// so the second call has to include the params again.
router.post(
  '/:id/documents',
  driverOnly,
  withId,
  upload,
  validate({ params: schemas.idParams, body: schemas.uploadDocumentBody }),
  async (req, res) => {
    if (!req.file) {
      throw new ApiError(422, 'VALIDATION_ERROR', 'Request validation failed', [
        { field: 'body.file', message: 'A file is required' },
      ]);
    }
    const data = await vehicleService.uploadDocument(
      req.user,
      req.validated.params.id,
      req.validated.body.docType,
      req.file.buffer,
    );
    return respond(res, { status: 201, message: 'Document uploaded', data });
  },
);

// SCRUM-54
router.get('/:id/verification', driverOrAdmin, withId, async (req, res) => {
  const data = await vehicleService.getVerification(req.user, req.validated.params.id);
  return respond(res, { message: 'Verification status loaded', data });
});

router.post('/:id/verification/submit', driverOnly, withId, async (req, res) => {
  const data = await vehicleService.submitVerification(req.user, req.validated.params.id);
  return respond(res, { message: 'Submitted for verification', data });
});

module.exports = router;
