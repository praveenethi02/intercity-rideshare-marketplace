const crypto = require('node:crypto');
const db = require('../../db');
const env = require('../../config/env');
const ApiError = require('../../utils/ApiError');
const sms = require('../../services/sms');
const { hashesMatch } = require('./token.service');

const OTP_PURPOSE = Object.freeze({ REGISTER: 'REGISTER', PASSWORD_RESET: 'PASSWORD_RESET' });

const invalidOtp = () =>
  new ApiError(400, 'OTP_INVALID_OR_EXPIRED', 'The code is incorrect or has expired');

/** Six-digit codes are easy to brute force if leaked, so the hash is keyed with a secret. */
function hashCode(phone, purpose, code) {
  return crypto
    .createHmac('sha256', env.OTP_HMAC_SECRET)
    .update(`${phone}:${purpose}:${code}`)
    .digest('hex');
}

async function assertCanSend(phone, purpose) {
  const { rows } = await db.query(
    `SELECT count(*)::int AS sent_last_hour,
            max(created_at) > now() - make_interval(secs => $3::double precision) AS in_cooldown
     FROM otp_codes
     WHERE phone = $1 AND purpose = $2 AND created_at > now() - interval '1 hour'`,
    [phone, purpose, env.OTP_RESEND_COOLDOWN_SECONDS],
  );

  if (rows[0].in_cooldown) {
    throw new ApiError(429, 'OTP_COOLDOWN', 'Please wait before requesting another code');
  }
  if (rows[0].sent_last_hour >= env.OTP_MAX_PER_HOUR) {
    throw new ApiError(429, 'OTP_LIMIT_REACHED', 'Too many codes requested. Try again later.');
  }
}

const invalidateActive = (phone, purpose, client = db) =>
  client.query(
    `UPDATE otp_codes SET consumed_at = now()
     WHERE phone = $1 AND purpose = $2 AND consumed_at IS NULL`,
    [phone, purpose],
  );

/** Creates a new code, cancelling any earlier one, and sends it by SMS. */
async function issue(phone, purpose) {
  await assertCanSend(phone, purpose);

  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');

  await db.transaction(async (tx) => {
    await invalidateActive(phone, purpose, tx);
    await tx.query(
      `INSERT INTO otp_codes (phone, purpose, code_hash, expires_at)
       VALUES ($1, $2, $3, now() + make_interval(secs => $4::double precision))`,
      [phone, purpose, hashCode(phone, purpose, code), env.OTP_TTL_SECONDS],
    );
  });

  const minutes = Math.ceil(env.OTP_TTL_SECONDS / 60);
  try {
    await sms.send(
      phone,
      `Your Intercity Rideshare code is ${code}. It expires in ${minutes} minutes. Do not share it.`,
    );
  } catch (error) {
    await invalidateActive(phone, purpose);
    console.error('SMS delivery failed:', error.message);
    throw new ApiError(502, 'SMS_DELIVERY_FAILED', 'Could not send the code. Please try again.');
  }
}

/** Checks a code and uses it up. Throws if it is wrong, expired or has had too many attempts. */
async function consume(phone, purpose, code) {
  const { rows } = await db.query(
    `SELECT id, code_hash FROM otp_codes
     WHERE phone = $1 AND purpose = $2 AND consumed_at IS NULL AND expires_at > now()
     ORDER BY created_at DESC
     LIMIT 1`,
    [phone, purpose],
  );
  const otp = rows[0];
  if (!otp) throw invalidOtp();

  // Counted before comparing, in one statement, so parallel guesses cannot exceed the limit.
  const counted = await db.query(
    `UPDATE otp_codes SET attempts = attempts + 1
     WHERE id = $1 AND consumed_at IS NULL AND attempts < $2
     RETURNING id`,
    [otp.id, env.OTP_MAX_ATTEMPTS],
  );
  if (counted.rows.length === 0) {
    await invalidateActive(phone, purpose);
    throw new ApiError(429, 'OTP_TOO_MANY_ATTEMPTS', 'Too many wrong codes. Request a new one.');
  }

  if (!hashesMatch(hashCode(phone, purpose, code), otp.code_hash)) throw invalidOtp();

  const used = await db.query(
    'UPDATE otp_codes SET consumed_at = now() WHERE id = $1 AND consumed_at IS NULL RETURNING id',
    [otp.id],
  );
  if (used.rows.length === 0) throw invalidOtp();
}

module.exports = { OTP_PURPOSE, issue, consume, invalidOtp };
