const { Router } = require('express');
const { z } = require('zod');
const db = require('../../db');
const authenticate = require('../../middleware/authenticate');
const requireRole = require('../../middleware/require-role');
const validate = require('../../middleware/validate');
const ApiError = require('../../utils/ApiError');
const respond = require('../../utils/respond');
const sessionRepository = require('../auth/session.repository');
const userRepository = require('../users/user.repository');
const { ROLES, USER_STATUS } = require('../users/user.constants');

const { toPublicUser } = userRepository;

const listUsersQuery = z.strictObject({
  role: z.enum(Object.values(ROLES)).optional(),
  status: z.enum(Object.values(USER_STATUS)).optional(),
  search: z.string().trim().min(1).max(100).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const userIdParams = z.strictObject({ id: z.uuid() });

const updateStatusBody = z.strictObject({
  status: z.enum([USER_STATUS.ACTIVE, USER_STATUS.SUSPENDED]),
});

async function findUserOr404(id) {
  const user = await userRepository.findById(id);
  if (!user) throw new ApiError(404, 'USER_NOT_FOUND', 'User not found');
  return user;
}

const router = Router();

router.use(authenticate, requireRole(ROLES.ADMIN));

router.get('/users', validate({ query: listUsersQuery }), async (req, res) => {
  const { page, limit } = req.validated.query;
  const { users, total } = await userRepository.search(req.validated.query);
  return respond(res, {
    message: 'Users loaded',
    data: { users: users.map(toPublicUser) },
    meta: { page, limit, total, totalPages: Math.ceil(total / limit) },
  });
});

router.get('/users/:id', validate({ params: userIdParams }), async (req, res) => {
  const user = await findUserOr404(req.validated.params.id);
  return respond(res, { message: 'User loaded', data: { user: toPublicUser(user) } });
});

/** Activates or suspends an account. Suspending signs the user out of every device. */
router.patch(
  '/users/:id/status',
  validate({ params: userIdParams, body: updateStatusBody }),
  async (req, res) => {
    const { id } = req.validated.params;
    const { status } = req.validated.body;

    if (id === req.user.id) {
      throw new ApiError(403, 'CANNOT_CHANGE_OWN_STATUS', 'You cannot change your own status');
    }

    const target = await findUserOr404(id);
    if (target.status === USER_STATUS.PENDING_VERIFICATION) {
      throw new ApiError(409, 'PHONE_NOT_VERIFIED', 'This user has not verified their phone');
    }

    const user = await db.transaction(async (tx) => {
      const updated =
        target.status === status
          ? target
          : await userRepository.changeStatus(id, target.status, status, tx);
      if (!updated) throw new ApiError(409, 'CONFLICT', 'The account status has changed');

      if (status === USER_STATUS.SUSPENDED) {
        await sessionRepository.revokeAllForUser(id, {}, tx);
      }
      return updated;
    });

    return respond(res, { message: 'User status updated', data: { user: toPublicUser(user) } });
  },
);

module.exports = router;
