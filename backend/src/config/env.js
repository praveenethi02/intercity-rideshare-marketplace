require('dotenv').config({ quiet: true });
const { z } = require('zod');

const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(4000),
    DATABASE_URL: z.string().min(1),
    CORS_ORIGINS: z.string().default(''),
    TRUST_PROXY: z.coerce.number().int().min(0).default(0),
    PUBLIC_BASE_URL: z.string().url().default('http://localhost:4000'),
    UPLOAD_DIR: z.string().min(1).default('uploads'),

    JWT_ACCESS_SECRET: z.string().min(32),
    OTP_HMAC_SECRET: z.string().min(32),
    JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().positive().default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
    BCRYPT_ROUNDS: z.coerce.number().int().min(4).max(15).default(12),

    OTP_TTL_SECONDS: z.coerce.number().int().positive().default(300),
    OTP_MAX_ATTEMPTS: z.coerce.number().int().positive().default(5),
    OTP_RESEND_COOLDOWN_SECONDS: z.coerce.number().int().min(0).default(60),
    OTP_MAX_PER_HOUR: z.coerce.number().int().positive().default(5),
    SMS_PROVIDER: z.enum(['console']).default('console'),

    RATE_LIMIT_ENABLED: z
      .enum(['true', 'false'])
      .default('true')
      .transform((value) => value === 'true'),
    AUTH_RATE_LIMIT_WINDOW_MINUTES: z.coerce.number().int().positive().default(15),
    AUTH_RATE_LIMIT_MAX: z.coerce.number().int().positive().default(30),
  })
  .refine((env) => !(env.NODE_ENV === 'production' && env.SMS_PROVIDER === 'console'), {
    message: 'SMS_PROVIDER=console prints OTP codes to the log and cannot be used in production',
    path: ['SMS_PROVIDER'],
  });

const result = schema.safeParse(process.env);

if (!result.success) {
  const problems = result.error.issues.map((issue) => `  ${issue.path.join('.')}: ${issue.message}`);
  throw new Error(`Invalid environment configuration:\n${problems.join('\n')}`);
}

module.exports = result.data;
