/**
 * Sends SMS messages. Only the development provider exists so far: it prints the message to
 * the server log, and config validation refuses it in production. To add a real gateway, add
 * a provider here and to SMS_PROVIDER in config/env.js.
 */
const sms = {
  async send(phone, message) {
    console.info(`[SMS to ${phone}] ${message}`);
  },
};

module.exports = sms;
