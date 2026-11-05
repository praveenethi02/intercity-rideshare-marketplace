import { LayoutGrid, LogOut, Navigation } from 'lucide-react';
import { NavLink, Outlet } from 'react-router-dom';
import Avatar from '../components/Avatar';
import { logout, useSession } from '../lib/auth';

export default function AdminLayout({ navItems }) {
  const session = useSession();
  const name = session?.user?.fullName ?? 'Admin';

  return (
    <div className="shell">
      <aside className="shell-sidebar">
        <div className="shell-brand">
          <span className="brand-mark">
            <Navigation size={18} aria-hidden="true" />
          </span>
          <div>
            <strong>Intercity</strong>
            <small>Admin console</small>
          </div>
        </div>

        <nav className="shell-nav" aria-label="Main">
          {navItems.map((item) => {
            const Icon = item.icon ?? LayoutGrid;
            return (
              <NavLink key={item.path} to={item.path}>
                <Icon size={18} aria-hidden="true" />
                {item.label}
              </NavLink>
            );
          })}
        </nav>

        <div className="shell-user">
          <Avatar name={name} />
          <div className="shell-user-text">
            <strong>{name}</strong>
            <small>Administrator</small>
          </div>
        </div>
      </aside>

      <div className="shell-content">
        <header className="shell-topbar">
          <button type="button" className="button" onClick={logout}>
            <LogOut size={16} aria-hidden="true" />
            Log out
          </button>
        </header>
        <main className="shell-main">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
