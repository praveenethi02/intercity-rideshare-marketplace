// Trip lifecycle (state machine):
//   DRAFT -> SCHEDULED -> IN_PROGRESS -> COMPLETED
//   DRAFT or SCHEDULED -> CANCELLED
const { TRIP_STATUS: S } = require('./trip.constants');

const TRANSITIONS = Object.freeze({
  [S.DRAFT]: [S.SCHEDULED, S.CANCELLED],
  [S.SCHEDULED]: [S.IN_PROGRESS, S.CANCELLED],
  [S.IN_PROGRESS]: [S.COMPLETED],
  [S.COMPLETED]: [],
  [S.CANCELLED]: [],
});

const canTransition = (from, to) => (TRANSITIONS[from] || []).includes(to);

/** API fields a driver may still change. 'ALL' for drafts. */
function editableFields(status, hasReservations) {
  if (status === S.DRAFT) return 'ALL';
  if (status === S.SCHEDULED && !hasReservations) {
    return ['notes', 'estimatedArrivalAt', 'basePriceCents', 'seatsOffered'];
  }
  if (status === S.SCHEDULED) return ['notes', 'estimatedArrivalAt'];
  return [];
}

module.exports = { TRANSITIONS, canTransition, editableFields };
