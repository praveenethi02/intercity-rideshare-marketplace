import api from '../../lib/api';

/** Asks for one row only and returns meta.total, the number of matching rows. */
const countOf = (path, params, signal) =>
  api.get(path, { params: { ...params, page: 1, limit: 1 }, signal }).then((res) => res.data.meta.total);

/** Everything the dashboard shows, loaded in parallel from the existing admin APIs. */
export async function loadDashboard(signal) {
  const [users, passengers, drivers, pendingDrivers, pendingVehicles, approvedVehicles, recentUsers] =
    await Promise.all([
      countOf('/admin/users', {}, signal),
      countOf('/admin/users', { role: 'PASSENGER' }, signal),
      countOf('/admin/users', { role: 'DRIVER' }, signal),
      countOf('/admin/verifications', { type: 'DRIVER', status: 'PENDING' }, signal),
      countOf('/admin/vehicles', { verificationStatus: 'PENDING' }, signal),
      countOf('/admin/vehicles', { verificationStatus: 'APPROVED' }, signal),
      api.get('/admin/users', { params: { page: 1, limit: 5 }, signal }).then((res) => res.data.data.users),
    ]);

  return { users, passengers, drivers, pendingDrivers, pendingVehicles, approvedVehicles, recentUsers };
}