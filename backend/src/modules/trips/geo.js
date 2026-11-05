// Pure geography helpers (no database), easy to unit test.
const EARTH_RADIUS_KM = 6371;
const toRad = (deg) => (deg * Math.PI) / 180;

/** Great-circle distance between two { lat, lng } points in km. */
function haversineKm(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

/**
 * Straight-line distance times this factor approximates road distance.
 * Replace with Google Directions distances later for accuracy.
 */
const ROAD_FACTOR = 1.25;

/** Adds distance_from_start_m (road estimate, metres) to each stop. */
function withDistanceFromStart(stops) {
  let totalKm = 0;
  return stops.map((stop, i) => {
    if (i > 0) totalKm += haversineKm(stops[i - 1], stop) * ROAD_FACTOR;
    return { ...stop, distance_from_start_m: Math.round(totalKm * 1000) };
  });
}

/** Lat/lng box around a point, used to pre-filter in SQL before the exact distance check. */
function boundingBox(point, radiusKm) {
  const dLat = radiusKm / 111.32;
  const dLng = radiusKm / (111.32 * Math.max(Math.cos(toRad(point.lat)), 1e-6));
  return {
    minLat: point.lat - dLat,
    maxLat: point.lat + dLat,
    minLng: point.lng - dLng,
    maxLng: point.lng + dLng,
  };
}

module.exports = { haversineKm, withDistanceFromStart, boundingBox, ROAD_FACTOR };
