// Holds the signed-in admin and their tokens. Uses sessionStorage, so closing the tab signs out.
const STORAGE_KEY = 'rideshare.admin.session';

function readStored() {
  try {
    return JSON.parse(sessionStorage.getItem(STORAGE_KEY));
  } catch {
    return null;
  }
}

let session = readStored();
const listeners = new Set();

export function getSession() {
  return session;
}

export function setSession(next) {
  session = next;
  if (next) {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } else {
    sessionStorage.removeItem(STORAGE_KEY);
  }
  listeners.forEach((listener) => listener());
}

export function subscribe(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
