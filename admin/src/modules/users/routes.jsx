import { Users } from 'lucide-react';
import UserDetailPage from './UserDetailPage';
import UsersPage from './UsersPage';

// Spread into App.jsx. Only the entry with `label` appears in the sidebar.
const userRoutes = [
  { path: '/users', element: <UsersPage />, label: 'Users', icon: Users },
  { path: '/users/:id', element: <UserDetailPage /> },
];

export default userRoutes;
