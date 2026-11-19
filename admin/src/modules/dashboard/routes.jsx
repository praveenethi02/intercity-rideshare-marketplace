import { LayoutDashboard } from 'lucide-react';
import DashboardPage from './DashboardPage';

// Spread into App.jsx first, so the dashboard is the first sidebar item and the home page.
const dashboardRoutes = [
  { path: '/dashboard', element: <DashboardPage />, label: 'Dashboard', icon: LayoutDashboard },
];

export default dashboardRoutes;