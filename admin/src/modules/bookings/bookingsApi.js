import api from '../../lib/api';

const BASE = '/admin/bookings';

const unwrap = (res) => res.data; // { success, message, data, meta }

// SCRUM-231: read-only. Admins cannot create or cancel bookings here.
export const bookingsApi = {
  list: (params, signal) => api.get(BASE, { params, signal }).then(unwrap),
  get: (id, signal) => api.get(`${BASE}/${id}`, { signal }).then(unwrap),
};

export const BOOKING_STATUS_LABELS = {
  CONFIRMED: 'Confirmed',
  CANCELLED: 'Cancelled',
};

export const TRIP_STATUS_LABELS = {
  SCHEDULED: 'Scheduled',
  IN_PROGRESS: 'On the way',
  COMPLETED: 'Completed',
  CANCELLED: 'Trip cancelled',
};

/** 250000 cents -> "LKR 2,500" */
export function formatLkr(cents) {
  return `LKR ${(cents / 100).toLocaleString('en-LK', { maximumFractionDigits: 2 })}`;
}

export function formatDateTime(value) {
  return value ? new Date(value).toLocaleString() : 'Not given';
}