const { Router } = require('express');
const authenticate = require('../../middleware/authenticate');
const validate = require('../../middleware/validate');
const { apiRateLimit } = require('../../middleware/rate-limit');
const respond = require('../../utils/respond');
const schemas = require('./rating.schemas');
const ratingService = require('./rating.service');

const router = Router();

const pageMeta = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit) });

router.use(apiRateLimit, authenticate);

router.post('/', validate({ body: schemas.createRating }), async (req, res) => {
  const rating = await ratingService.createRating(req.user, req.validated.body);
  return respond(res, { status: 201, message: 'Rating saved', data: { rating } });
});

router.get('/pending', async (req, res) => {
  const pending = await ratingService.listPending(req.user);
  return respond(res, { message: 'Pending ratings loaded', data: { pending } });
});

router.get('/mine', validate({ query: schemas.mineQuery }), async (req, res) => {
  const query = req.validated.query;
  const { ratings, total } = await ratingService.listMine(req.user, query);
  return respond(res, { message: 'Ratings loaded', data: { ratings }, meta: pageMeta(query, total) });
});

router.get(
  '/users/:userId',
  validate({ params: schemas.userIdParams, query: schemas.receivedQuery }),
  async (req, res) => {
    const query = req.validated.query;
    const { averageRating, ratingCount, ratings, total } = await ratingService.listReceived(
      req.validated.params.userId,
      query,
    );
    return respond(res, {
      message: 'Ratings loaded',
      data: { averageRating, ratingCount, ratings },
      meta: pageMeta(query, total),
    });
  },
);

module.exports = router;
