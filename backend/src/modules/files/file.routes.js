const { Router } = require('express');
const storage = require('../../services/storage');
const ApiError = require('../../utils/ApiError');

const router = Router();

/** Serves private uploads. The signed link is the permission, so no token is needed. */
router.get('/:key', (req, res, next) => {
  const { key } = req.params;
  if (!storage.verify(key, req.query.expires, req.query.sig)) {
    throw new ApiError(403, 'FORBIDDEN', 'This link is invalid or has expired');
  }

  res.sendFile(
    key,
    {
      root: storage.dir,
      headers: {
        'Cache-Control': 'private, no-store',
        // Lets the admin web app, on another origin, preview documents.
        'Cross-Origin-Resource-Policy': 'cross-origin',
      },
    },
    (error) => {
      if (error && !res.headersSent) next(new ApiError(404, 'FILE_NOT_FOUND', 'File not found'));
    },
  );
});

module.exports = router;
