/** Sends the standard API envelope: { success, message, data, meta }. */
function respond(res, { status = 200, message = 'OK', data = null, meta = null } = {}) {
  return res.status(status).json({ success: true, message, data, meta });
}

module.exports = respond;
