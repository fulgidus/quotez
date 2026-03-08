import { Outlet } from '@tanstack/react-router';

export function PublicLayout() {
  return (
    <div data-testid="public-layout" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <main style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        <Outlet />
      </main>
    </div>
  );
}
