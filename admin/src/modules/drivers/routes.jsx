import { IdCard } from 'lucide-react';
import DriverDetailPage from './DriverDetailPage';
import DriverQueuePage from './DriverQueuePage';

// Spread into App.jsx. Only the entry with `label` appears in the sidebar.
const driverRoutes = [
  { path: '/drivers', element: <DriverQueuePage />, label: 'Drivers', icon: IdCard },
  { path: '/drivers/:id', element: <DriverDetailPage /> },
];

export default driverRoutes;
