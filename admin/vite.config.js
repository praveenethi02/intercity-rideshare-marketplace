import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  // The backend's CORS_ORIGINS allows this address by default.
  server: { port: 3000, strictPort: true },
});
