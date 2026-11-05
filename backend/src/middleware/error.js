const ApiError = require('../utils/ApiError');

const PG_UNIQUE_VIOLATION = '23505';

function notFound(req, res, next) {
  next(new ApiError(404, 'NOT_FOUND', `Route not found: ${req.method} ${req.path}`));
}

function toApiError(error) {
  if (error instanceof ApiError) return error;
  if (error.type === 'entity.parse.failed') {
    return new ApiError(400, 'INVALID_JSON', 'Request body is not valid JSON');
  }
  if (error.type === 'entity.too.large') {
    return new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Request body is too large');
  }
  if (error.code === PG_UNIQUE_VIOLATION) {
    return new ApiError(409, 'CONFLICT', 'A record with these details already exists');
  }
  return null;
}

// Express identifies error middleware by its four parameters, so `next` must stay.
// eslint-disable-next-line no-unused-vars
function errorHandler(error, req, res, next) {
  const apiError = toApiError(error);

  if (!apiError) {
    console.error(`Unhandled error on ${req.method} ${req.path}:`, error);
    return res.status(500).json({
      success: false,
      message: 'Something went wrong',
      data: null,
      meta: { code: 'INTERNAL_ERROR' },
    });
  }

  return res.status(apiError.status).json({
    success: false,
    message: apiError.message,
    data: null,
    meta: { code: apiError.code, ...(apiError.details ? { details: apiError.details } : {}) },
  });
}

module.exports = { notFound, errorHandler };
