import { Navigate, useLocation } from 'react-router-dom';
import { isAdmin, useSession } from '../lib/auth';

/** Sends anyone who is not a signed-in admin to the login page. The API enforces this as well. */
export default function RequireAdmin({ children }) {
  const session = useSession();
  const location = useLocation();

  if (!isAdmin(session)) {
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />;
  }
  return children;
}
