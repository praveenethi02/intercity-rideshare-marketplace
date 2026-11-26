import { Ticket } from 'lucide-react';
import BookingDetailPage from './BookingDetailPage';
import BookingsPage from './BookingsPage';

// Spread into App.jsx. Only the entry with `label` appears in the sidebar.
const bookingRoutes = [
  { path: '/bookings', element: <BookingsPage />, label: 'Bookings', icon: Ticket },
  { path: '/bookings/:id', element: <BookingDetailPage /> },
];

export default bookingRoutes;