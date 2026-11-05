import { NavLink, Outlet } from 'react-router-dom';
import { logout, useSession } from '../lib/auth';

export default function AdminLayout({ navItems }) {
  const session = useSession();

  return (
    <div className="shell">
      <header className="shell-header">
        <strong className="shell-brand">Rideshare Admin</strong>
        <div className="shell-account">
          <span>{session?.user?.fullName}</span>
          <button type="button" className="button" onClick={logout}>
            Log out
          </button>
        </div>
      </header>

      <div className="shell-body">
        <nav className="shell-nav" aria-label="Main">
          {navItems.map((item) => (
            <NavLink key={item.path} to={item.path}>
              {item.label}
            </NavLink>
          ))}
        </nav>
        <main className="shell-main">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
