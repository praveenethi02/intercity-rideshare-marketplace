const { createHmac, randomUUID, timingSafeEqual } = require('node:crypto');
const { mkdir, unlink, writeFile } = require('node:fs/promises');
const path = require('node:path');
const env = require('../config/env');

const LINK_TTL_SECONDS = 900;
const KEY_PATTERN = /^[0-9a-f-]{36}\.(jpg|png|pdf)$/;

const dir = path.resolve(__dirname, '..', '..', env.UPLOAD_DIR);

// Derived, so file links cannot be forged even though they need no separate secret to configure.
const signingKey = createHmac('sha256', env.JWT_ACCESS_SECRET).update('file-links').digest();
const sign = (key, expires) => createHmac('sha256', signingKey).update(`${key}.${expires}`).digest('hex');

/**
 * Works out the real file type from the first bytes, because the file name and Content-Type
 * header are chosen by the client and can be faked. Returns null for anything else.
 */
function detectFileType(buffer) {
  const starts = (...bytes) => bytes.every((byte, i) => buffer[i] === byte);
  if (starts(0xff, 0xd8, 0xff)) return 'jpg';
  if (starts(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) return 'png';
  if (starts(0x25, 0x50, 0x44, 0x46, 0x2d)) return 'pdf';
  return null;
}

async function save(buffer, extension) {
  await mkdir(dir, { recursive: true });
  const key = `${randomUUID()}.${extension}`;
  await writeFile(path.join(dir, key), buffer);
  return key;
}

async function remove(key) {
  await unlink(path.join(dir, key)).catch((error) => {
    if (error.code !== 'ENOENT') throw error;
  });
}

function signedUrl(key) {
  const expires = Math.floor(Date.now() / 1000) + LINK_TTL_SECONDS;
  return `${env.PUBLIC_BASE_URL}/api/v1/files/${key}?expires=${expires}&sig=${sign(key, expires)}`;
}

function verify(key, expires, sig) {
  if (!KEY_PATTERN.test(key) || typeof sig !== 'string') return false;
  if (!/^\d+$/.test(String(expires)) || Number(expires) < Date.now() / 1000) return false;
  const expected = Buffer.from(sign(key, expires));
  const given = Buffer.from(sig);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

module.exports = { dir, detectFileType, save, remove, signedUrl, verify };
