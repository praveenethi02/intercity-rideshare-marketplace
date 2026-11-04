const SRI_LANKAN_MOBILE = /^(?:\+94|94|0)(7\d{8})$/;

/** Converts 0771234567, 94771234567 or +94771234567 to +94771234567. Returns null if invalid. */
function normalizePhone(value) {
  const match = String(value).replace(/[\s-]/g, '').match(SRI_LANKAN_MOBILE);
  return match ? `+94${match[1]}` : null;
}

module.exports = { normalizePhone };
