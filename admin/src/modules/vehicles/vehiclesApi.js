// Calls to /api/v1/admin/vehicles through M1's axios instance (lib/api.js).
// Works whether M1 exports it as `export default api` or `export const api`.
import * as apiLib from '../../lib/api';

const api = apiLib.default || apiLib.api;

// If M1's axios baseURL does NOT already end in /api/v1, change this to '/api/v1/admin/vehicles'.
const BASE = '/admin/vehicles';

const unwrap = (res) => res.data; // { success, message, data, meta }

export const vehiclesApi = {
  list: (params) => api.get(BASE, { params }).then(unwrap),
  get: (id) => api.get(`${BASE}/${id}`).then(unwrap),
  decide: (id, body) => api.patch(`${BASE}/${id}/verification`, body).then(unwrap),
  setStatus: (id, body) => api.patch(`${BASE}/${id}/status`, body).then(unwrap),
};

/** "/uploads/x.jpg" -> "http://localhost:3000/uploads/x.jpg" (backend origin). */
export function fileHref(fileUrl) {
  if (!fileUrl || /^https?:\/\//.test(fileUrl)) return fileUrl;
  const base = api.defaults?.baseURL || window.location.origin;
  return new URL(base, window.location.origin).origin + fileUrl;
}

/** Error envelope -> readable message. */
export function errorMessage(err) {
  const body = err?.response?.data;
  if (body?.message) {
    const first = body.meta?.details?.[0]?.message;
    return first && first !== body.message ? `${body.message}: ${first}` : body.message;
  }
  return err?.message || 'Something went wrong';
}

export const DOC_LABELS = {
  REGISTRATION_CERT: 'Registration certificate',
  REVENUE_LICENSE: 'Revenue licence',
  INSURANCE: 'Insurance',
  PHOTO_FRONT: 'Photo – front',
  PHOTO_BACK: 'Photo – back',
  PHOTO_INTERIOR: 'Photo – interior',
};

export const VEHICLE_TYPES = ['CAR', 'SUV', 'VAN', 'MINIBUS', 'BUS', 'PICKUP', 'LORRY'];
export const STATUSES = ['PENDING', 'APPROVED', 'REJECTED', 'NOT_SUBMITTED'];
