import VehicleQueuePage from './VehicleQueuePage';
import VehicleDetailPage from './VehicleDetailPage';

// Spread into M1's App.jsx. Only the entry with `label` should appear in the sidebar.
const vehicleRoutes = [
  { path: '/vehicles', element: <VehicleQueuePage />, label: 'Vehicles' },
  { path: '/vehicles/:id', element: <VehicleDetailPage /> },
];

export default vehicleRoutes;
export { vehicleRoutes };
