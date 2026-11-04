const ApiError = require('../utils/ApiError');

/**
 * Validates parts of the request against zod schemas, e.g. validate({ body: schema }).
 * Parsed values are available on req.validated.body, .query and .params.
 */
function validate(schemas) {
  return (req, res, next) => {
    req.validated = {};
    const details = [];

    for (const [part, schema] of Object.entries(schemas)) {
      const result = schema.safeParse(req[part] ?? {});
      if (result.success) {
        req.validated[part] = result.data;
      } else {
        for (const issue of result.error.issues) {
          details.push({ field: [part, ...issue.path].join('.'), message: issue.message });
        }
      }
    }

    if (details.length > 0) {
      throw new ApiError(422, 'VALIDATION_ERROR', 'Request validation failed', details);
    }
    next();
  };
}

module.exports = validate;
