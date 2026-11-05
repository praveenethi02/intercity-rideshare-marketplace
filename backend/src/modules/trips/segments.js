// Seat inventory per route segment (pure functions).
// Stops 0..n-1 make legs 0..n-2 (leg i joins stop i and stop i + 1).
// A passenger from stop `from` to stop `to` uses legs from..to-1.

function legsFor(fromStop, toStop) {
  if (!Number.isInteger(fromStop) || !Number.isInteger(toStop) || fromStop < 0 || toStop <= fromStop) {
    throw new RangeError('The drop stop must come after the pickup stop');
  }
  return Array.from({ length: toStop - fromStop }, (_, i) => fromStop + i);
}

/** seatsReservedByLeg[i] = seats taken on leg i. Free seats = offered - busiest leg used. */
function availableSeats(seatsOffered, seatsReservedByLeg, fromStop, toStop) {
  const used = legsFor(fromStop, toStop).map((leg) => seatsReservedByLeg[leg] || 0);
  return Math.max(0, seatsOffered - Math.max(0, ...used));
}

/** Segment price proportional to distance, rounded to LKR 10 (1000 cents). */
function segmentPriceCents(basePriceCents, totalM, fromM, toM) {
  if (totalM <= 0) return basePriceCents;
  const fraction = Math.min(1, Math.max(0, (toM - fromM) / totalM));
  return Math.round((basePriceCents * fraction) / 1000) * 1000;
}

module.exports = { legsFor, availableSeats, segmentPriceCents };
