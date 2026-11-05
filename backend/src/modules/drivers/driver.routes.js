const { Router } = require('express');
const multer = require('multer');
const authenticate = require('../../middleware/authenticate');
const validate = require('../../middleware/validate');
const ApiError = require('../../utils/ApiError');
const respond = require('../../utils/respond');
const driverRepository = require('./driver.repository');
const schemas = require('./driver.schemas');
const driverService = require('./driver.service');

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

/**
 * Checks for a driver profile rather than the user's role, because PUT /users/me/role lets a
 * driver switch role and they should still be able to manage their driver details.
 */
async function requireDriver(req, res, next) {
  req.driver = await driverRepository.findByUserId(req.user.id);
  if (!req.driver) throw new ApiError(403, 'FORBIDDEN', 'Only drivers can do this');
  next();
}

const pageMeta = ({ page, limit }, total) => ({
  page,
  limit,
  total,
  totalPages: Math.ceil(total / limit),
});

const router = Router();

router.use(authenticate);

router.post('/', validate({ body: schemas.register }), async (req, res) => {
  const driver = await driverService.register(req.user, req.validated.body);
  return respond(res, { status: 201, message: 'Driver profile created', data: { driver } });
});

// The /me routes must come before /:id, or "me" would be read as an id.
router.get('/me', requireDriver, async (req, res) => {
  const driver = await driverService.toProfile(req.driver);
  return respond(res, { message: 'Driver profile loaded', data: { driver } });
});

router.patch('/me', requireDriver, validate({ body: schemas.update }), async (req, res) => {
  const driver = await driverService.update(req.driver, req.validated.body);
  return respond(res, { message: 'Driver profile updated', data: { driver } });
});

router.post(
  '/me/documents',
  requireDriver,
  upload,
  validate({ body: schemas.documentBody }),
  async (req, res) => {
    if (!req.file) {
      throw new ApiError(422, 'VALIDATION_ERROR', 'Request validation failed', [
        { field: 'body.file', message: 'A file is required' },
      ]);
    }
    const document = await driverService.addDocument(
      req.driver,
      req.validated.body.type,
      req.file.buffer,
    );
    return respond(res, { status: 201, message: 'Document uploaded', data: { document } });
  },
);

router.get('/me/verification', requireDriver, async (req, res) => {
  const verification = await driverService.getVerification(req.driver);
  return respond(res, { message: 'Verification status loaded', data: { verification } });
});

router.get('/me/trips', requireDriver, validate({ query: schemas.tripQuery }), async (req, res) => {
  const { trips, total } = await driverService.listTrips(req.driver, req.validated.query);
  return respond(res, {
    message: 'Trips loaded',
    data: { trips },
    meta: pageMeta(req.validated.query, total),
  });
});

router.get(
  '/me/earnings',
  requireDriver,
  validate({ query: schemas.earningsQuery }),
  async (req, res) => {
    const earnings = await driverService.getEarnings(req.driver, req.validated.query);
    return respond(res, { message: 'Earnings loaded', data: { earnings } });
  },
);

router.get('/:id', validate({ params: schemas.driverIdParams }), async (req, res) => {
  const driver = await driverService.getPublicProfile(req.validated.params.id);
  return respond(res, { message: 'Driver loaded', data: { driver } });
});

module.exports = { router, pageMeta };
