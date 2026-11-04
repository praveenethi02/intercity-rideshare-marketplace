const ROLES = Object.freeze({
  PASSENGER: 'PASSENGER',
  DRIVER: 'DRIVER',
  CARGO_CUSTOMER: 'CARGO_CUSTOMER',
  ADMIN: 'ADMIN',
});

/** Roles a user may pick for themselves. ADMIN accounts are only created by the seed script. */
const SELECTABLE_ROLES = Object.freeze([ROLES.PASSENGER, ROLES.DRIVER, ROLES.CARGO_CUSTOMER]);

const USER_STATUS = Object.freeze({
  PENDING_VERIFICATION: 'PENDING_VERIFICATION',
  ACTIVE: 'ACTIVE',
  /** Closed by the user, who can reopen it. */
  DEACTIVATED: 'DEACTIVATED',
  /** Closed by an admin. Only an admin can reopen it. */
  SUSPENDED: 'SUSPENDED',
});

module.exports = { ROLES, SELECTABLE_ROLES, USER_STATUS };
