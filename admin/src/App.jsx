import { Navigate, Route, Routes } from 'react-router-dom';
import AdminLayout from './layout/AdminLayout';
import RequireAdmin from './layout/RequireAdmin';
import bookingRoutes from './modules/bookings/routes';
import dashboardRoutes from './modules/dashboard/routes';
import driverRoutes from './modules/drivers/routes';
import userRoutes from './modules/users/routes';
import vehicleRoutes from './modules/vehicles/routes';
import LoginPage from './pages/LoginPage';
import NotFoundPage from './pages/NotFoundPage';

// Each module exports an array of { path, element, label }. Add yours here.
// Routes with a label appear in the sidebar.
const moduleRoutes = [...dashboardRoutes, ...userRoutes, ...vehicleRoutes, ...driverRoutes, ...bookingRoutes];
const navItems = moduleRoutes.filter((route) => route.label);

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireAdmin>
            <AdminLayout navItems={navItems} />
          </RequireAdmin>
        }
      >
        <Route path="/" element={<Navigate to={navItems[0].path} replace />} />
        {moduleRoutes.map((route) => (
          <Route key={route.path} path={route.path} element={route.element} />
        ))}
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  );
}
