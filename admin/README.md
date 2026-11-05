# Intercity Rideshare Admin

React and Vite admin dashboard. It uses the [backend API](../backend/README.md).

## Run it locally

Start the backend first. You need an admin account, which `npm run seed:admin` creates in `backend/`.

```bash
cd admin
npm install
cp .env.example .env
npm run dev
```

The dashboard runs on `http://localhost:3000`. To use another port, change it in `vite.config.js` and add the address to `CORS_ORIGINS` in `backend/.env`.

## Adding your pages

1. Put your pages in `src/modules/<name>/`.
2. Call the API through the shared client, using paths relative to `/api/v1`. It adds the login token and refreshes it when it expires.

   ```js
   import api from '../../lib/api';

   api.get('/admin/vehicles');
   ```

3. Export your routes from `src/modules/<name>/routes.jsx`. Only entries with a `label` appear in the sidebar, and `icon` is an optional [Lucide](https://lucide.dev/icons) icon.

   ```jsx
   import { Car } from 'lucide-react';

   export default [
     { path: '/vehicles', element: <VehicleQueuePage />, label: 'Vehicles', icon: Car },
     { path: '/vehicles/:id', element: <VehicleDetailPage /> },
   ];
   ```

4. Add them to `moduleRoutes` in `src/App.jsx`.

   ```js
   const moduleRoutes = [...userRoutes, ...vehicleRoutes];
   ```

Start your CSS class names with a prefix for your module, such as `vh-`, so they do not clash with other modules. Use the colour variables at the top of `src/shell.css`, such as `var(--brand-500)`. They match the Figma design system.

## Sign-in

Only accounts with the `ADMIN` role can log in here. The check in this app only controls what is shown: the API enforces access on every request.

Tokens are kept in `sessionStorage`, so closing the tab signs the admin out.

## Checks

```bash
npm run lint
npm run build
```
