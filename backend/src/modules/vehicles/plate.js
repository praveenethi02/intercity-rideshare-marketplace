// SCRUM-49: Sri Lankan number plate normalisation.
//
// Accepted (after normalising):
//   WP CAB-1234   province + 3 letters + 4 digits (current format)
//   CAB-1234      3 letters + 4 digits
//   KX-1234       2 letters + 4 digits
//   65-1234       2 digits + 4 digits (old)
//   250-1234      3 digits + 4 digits (old)
//
// Normalising means: trim, UPPERCASE, single spaces, any dash type -> "-",
// no spaces around "-", and insert "-" before the last 4 digits if it is missing
// ("wp cab 1234" -> "WP CAB-1234", "cab1234" -> "CAB-1234").

const PROVINCES = ['WP', 'CP', 'SP', 'NP', 'EP', 'NW', 'NC', 'UP', 'SG'];

const PLATE_REGEX = new RegExp(`^(?:(?:${PROVINCES.join('|')}) )?(?:[A-Z]{2,3}|\\d{2,3})-\\d{4}$`);

function normalizePlate(raw) {
  if (typeof raw !== 'string') return raw;
  let p = raw
    .toUpperCase()
    .replace(/[‐-―−_]/g, '-') // unicode dashes / underscore -> "-"
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\s*-\s*/g, '-');

  // missing dash before the final 4 digits: "CAB 1234" / "CAB1234" / "65 1234"
  if (!/-\d{4}$/.test(p)) {
    p = p.replace(/([A-Z]{2,3}|\d{2,3}) ?(\d{4})$/, '$1-$2');
  }
  return p;
}

function isValidPlate(normalized) {
  return typeof normalized === 'string' && PLATE_REGEX.test(normalized);
}

module.exports = { normalizePlate, isValidPlate, PROVINCES };
