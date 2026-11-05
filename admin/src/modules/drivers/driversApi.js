import api from '../../lib/api';

const QUEUE = '/admin/verifications';
const SEARCH_PAGE_SIZE = 100;

const unwrap = (res) => res.data; // { success, message, data, meta }

const getQueuePage = (params, signal) =>
  api.get(QUEUE, { params: { ...params, type: 'DRIVER' }, signal }).then(unwrap);

// The queue only holds the driver's id. Details are optional, so a failed lookup leaves them null.
const getUser = (id, signal) =>
  api
    .get(`/admin/users/${id}`, { signal })
    .then((res) => res.data.data.user)
    .catch(() => null);

const getPublicProfile = (id, signal) =>
  api
    .get(`/drivers/${id}`, { signal })
    .then((res) => res.data.data.driver)
    .catch(() => null);

/** The API has no route for one request, so this searches the queue until it finds it. */
async function findVerification(id, signal) {
  for (let page = 1; ; page += 1) {
    const body = await getQueuePage({ page, limit: SEARCH_PAGE_SIZE }, signal);
    const found = body.data.verifications.find((verification) => verification.id === id);
    if (found) return found;
    if (page * SEARCH_PAGE_SIZE >= body.meta.total) return null;
  }
}

export const driversApi = {
  /** One page of driver requests, each with its driver's account. */
  async listQueue(params, signal) {
    const body = await getQueuePage(params, signal);
    const items = await Promise.all(
      body.data.verifications.map(async (verification) => ({
        verification,
        user: await getUser(verification.subjectId, signal),
      })),
    );
    return { items, total: body.meta.total };
  },

  /** A request with its driver's account and public profile, or null if there is no such request. */
  async getReview(id, signal) {
    const verification = await findVerification(id, signal);
    if (!verification) return null;
    const [user, profile] = await Promise.all([
      getUser(verification.subjectId, signal),
      getPublicProfile(verification.subjectId, signal),
    ]);
    return { verification, user, profile };
  },

  decide: (id, body) => api.patch(`${QUEUE}/${id}`, body).then(unwrap),
};

export const DOCUMENT_LABELS = {
  LICENCE_FRONT: 'Licence (front)',
  LICENCE_BACK: 'Licence (back)',
  NIC_FRONT: 'NIC (front)',
  NIC_BACK: 'NIC (back)',
  PROFILE_PHOTO: 'Profile photo',
};

export const STATUSES = ['PENDING', 'APPROVED', 'REJECTED'];

export const REASON_MAX_LENGTH = 500;

export function formatDate(value) {
  return value ? new Date(value).toLocaleString('en-GB', { timeZone: 'Asia/Colombo' }) : '—';
}
