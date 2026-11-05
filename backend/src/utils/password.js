const bcrypt = require('bcryptjs');
const env = require('../config/env');

// Compared against when no account matches, so both login outcomes take similar time.
const DUMMY_HASH = bcrypt.hashSync('no-account-has-this-password', env.BCRYPT_ROUNDS);

const hashPassword = (password) => bcrypt.hash(password, env.BCRYPT_ROUNDS);

const verifyPassword = (password, hash) => bcrypt.compare(password, hash ?? DUMMY_HASH);

module.exports = { hashPassword, verifyPassword };
