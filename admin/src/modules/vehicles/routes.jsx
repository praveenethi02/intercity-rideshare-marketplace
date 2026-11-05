import { Car } from 'lucide-react';
import VehicleDetailPage from './VehicleDetailPage';
import VehicleQueuePage from './VehicleQueuePage';

// Spread into App.jsx. Only the entry with `label` appears in the sidebar.
const vehicleRoutes = [
  { path: '/vehicles', element: <VehicleQueuePage />, label: 'Vehicles', icon: Car },
  { path: '/vehicles/:id', element: <VehicleDetailPage /> },
];

export default vehicleRoutes;
