const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const env = require('./config/env');
const db = require('./db');
const respond = require('./utils/respond');
const ApiError = require('./utils/ApiError');
const { notFound, errorHandler } = require('./middleware/error');
const authRoutes = require('./modules/auth/auth.routes');
const userRoutes = require('./modules/users/user.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const { router: driverRoutes } = require('./modules/drivers/driver.routes');
const driverAdminRoutes = require('./modules/drivers/driver.admin.routes');
const fileRoutes = require('./modules/files/file.routes');

function createApp() {
  const app = express();

  app.set('trust proxy', env.TRUST_PROXY);
  app.use(helmet());
  app.use(
    cors({
      origin: env.CORS_ORIGINS.split(',')
        .map((origin) => origin.trim())
        .filter(Boolean),
    }),
  );
  app.use(express.json({ limit: '100kb' }));

  app.get('/health', async (req, res) => {
    try {
      await db.query('SELECT 1');
    } catch {
      throw new ApiError(503, 'DATABASE_UNAVAILABLE', 'Database is unavailable');
    }
    return respond(res, { message: 'Service is healthy', data: { status: 'ok' } });
  });

  app.use('/api/v1/auth', authRoutes);
  app.use('/api/v1/users', userRoutes);
  app.use('/api/v1/drivers', driverRoutes);
  app.use('/api/v1/files', fileRoutes);
  app.use('/api/v1/admin', driverAdminRoutes);
  app.use('/api/v1/admin', adminRoutes);

  app.use(notFound);
  app.use(errorHandler);

  return app;
}

module.exports = createApp;
