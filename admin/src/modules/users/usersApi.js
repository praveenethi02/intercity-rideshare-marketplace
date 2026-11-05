import api from '../../lib/api';

const BASE = '/admin/users';

const unwrap = (res) => res.data; // { success, message, data, meta }

export const usersApi = {
  list: (params, signal) => api.get(BASE, { params, signal }).then(unwrap),
  get: (id, signal) => api.get(`${BASE}/${id}`, { signal }).then(unwrap),
  setStatus: (id, status) => api.patch(`${BASE}/${id}/status`, { status }).then(unwrap),
};

export const ROLE_LABELS = {
  PASSENGER: 'Passenger',
  DRIVER: 'Driver',
  CARGO_CUSTOMER: 'Cargo customer',
  ADMIN: 'Admin',
};

export const STATUS_LABELS = {
  PENDING_VERIFICATION: 'Pending verification',
  ACTIVE: 'Active',
  DEACTIVATED: 'Deactivated',
  SUSPENDED: 'Suspended',
};
