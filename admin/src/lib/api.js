// Shared axios instance. Module API files import this and use paths relative to /api/v1.
import axios from 'axios';
import { getSession, setSession } from './session';

const baseURL = import.meta.env.VITE_API_URL || 'http://localhost:4000/api/v1';

const api = axios.create({ baseURL });

api.interceptors.request.use((config) => {
  const token = getSession()?.tokens?.accessToken;
  if (token && !config.headers.has('Authorization')) {
    config.headers.set('Authorization', `Bearer ${token}`);
  }
  return config;
});

// Refresh tokens work once, and reusing one ends the session, so parallel 401s share one refresh.
let refreshInFlight = null;

async function requestNewTokens() {
  const current = getSession();
  if (!current?.tokens?.refreshToken) {
    setSession(null);
    throw new Error('Not signed in');
  }

  try {
    const res = await axios.post(`${baseURL}/auth/refresh`, {
      refreshToken: current.tokens.refreshToken,
    });
    setSession({ ...current, tokens: res.data.data.tokens });
  } catch (error) {
    // No response means a network failure: stay signed in so that a retry can work.
    if (error.response) setSession(null);
    throw error;
  }
}

function refreshTokens() {
  refreshInFlight ??= requestNewTokens().finally(() => {
    refreshInFlight = null;
  });
  return refreshInFlight;
}

api.interceptors.response.use(undefined, async (error) => {
  const { config, response } = error;
  const canRefresh =
    response?.status === 401 && config && !config.retried && !config.url.startsWith('/auth/');
  if (!canRefresh) throw error;

  try {
    await refreshTokens();
  } catch {
    throw error;
  }

  config.retried = true;
  config.headers.delete('Authorization');
  return api(config);
});

/** Turns an API error envelope into a message for the user. */
export function errorMessage(error) {
  const body = error?.response?.data;
  if (body?.message) {
    const detail = body.meta?.details?.[0]?.message;
    return detail && detail !== body.message ? `${body.message}: ${detail}` : body.message;
  }
  return error?.response ? 'Something went wrong' : 'Cannot reach the server';
}

export default api;
export { api };
