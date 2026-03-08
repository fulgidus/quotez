import { Link, Outlet, useNavigate } from '@tanstack/react-router';
import { clearCredentials } from '../lib/auth';

export function AdminLayout() {
  const navigate = useNavigate();

  const handleLogout = () => {
    clearCredentials();
    navigate({ to: '/admin/login' });
  };

  return (
    <div data-testid="admin-layout" style={{ display: 'flex', minHeight: '100vh' }}>
      <aside
        data-testid="admin-nav"
        style={{
          width: '250px',
          backgroundColor: 'var(--color-surface)',
          borderRight: '1px solid var(--color-border)',
          padding: 'var(--spacing-lg)',
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--spacing-md)',
        }}
      >
        <h2 style={{ marginBottom: 'var(--spacing-md)' }}>Admin</h2>
        <nav style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          <Link
            to="/admin"
            activeProps={{ style: { color: 'var(--color-accent)' } }}
            activeOptions={{ exact: true }}
          >
            Dashboard
          </Link>
          <Link
            to="/admin/quotes"
            activeProps={{ style: { color: 'var(--color-accent)' } }}
          >
            Quotes
          </Link>
          <Link
            to="/admin/config"
            activeProps={{ style: { color: 'var(--color-accent)' } }}
          >
            Config
          </Link>
        </nav>
        <div style={{ marginTop: 'auto' }}>
          <button
            onClick={handleLogout}
            style={{
              background: 'none',
              border: 'none',
              color: 'var(--color-text-muted)',
              cursor: 'pointer',
              padding: 0,
              fontSize: '1rem',
            }}
          >
            Logout
          </button>
        </div>
      </aside>
      <main style={{ flex: 1, padding: 'var(--spacing-xl)' }}>
        <Outlet />
      </main>
    </div>
  );
}
