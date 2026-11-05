import { useSyncExternalStore } from 'react';
import api from './api';
import { getSession, setSession, subscribe } from './session';

const ADMIN_ROLE = 'ADMIN';

/** The signed-in admin's session, or null. Components re-render when it changes. */
export function useSession() {
  return useSyncExternalStore(subscribe, getSession);
}

export function isAdmin(session) {
  return session?.user?.role === ADMIN_ROLE;
}

export async function login(phone, password) {
  const res = await api.post('/auth/login', { phone, password });
  const { user, tokens } = res.data.data;

  if (user.role !== ADMIN_ROLE) {
    // Do not leave a session open for an account that cannot use this site.
    await api
      .post('/auth/logout', null, { headers: { Authorization: `Bearer ${tokens.accessToken}` } })
      .catch(() => {});
    throw new Error('This account is not an administrator');
  }

  setSession({ user, tokens });
}

export async function logout() {
  try {
    await api.post('/auth/logout');
  } catch {
    // The local session is cleared either way.
  } finally {
    setSession(null);
  }
}
