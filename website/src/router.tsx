import { createRouter, createRoute, createRootRoute, redirect } from '@tanstack/react-router';
import { PublicLayout } from './components/PublicLayout';
import { AdminLayout } from './components/AdminLayout';
import { PublicPage } from './routes/public';
import { AdminPage } from './routes/admin';
import { AdminQuotesPage } from './routes/admin-quotes';
import { AdminConfigPage } from './routes/admin-config';
import { LoginPage } from './routes/login';
import { getCredentials } from './lib/auth';

const rootRoute = createRootRoute();

const publicLayoutRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: 'public',
  component: PublicLayout,
});

const indexRoute = createRoute({
  getParentRoute: () => publicLayoutRoute,
  path: '/',
  component: PublicPage,
});

const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/admin/login',
  component: LoginPage,
  beforeLoad: () => {
    if (getCredentials()) {
      throw redirect({ to: '/admin' });
    }
  },
});

const adminLayoutRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: 'admin',
  component: AdminLayout,
  beforeLoad: () => {
    if (!getCredentials()) {
      throw redirect({ to: '/admin/login' });
    }
  },
});

const adminIndexRoute = createRoute({
  getParentRoute: () => adminLayoutRoute,
  path: '/admin',
  component: AdminPage,
});

const adminQuotesRoute = createRoute({
  getParentRoute: () => adminLayoutRoute,
  path: '/admin/quotes',
  component: AdminQuotesPage,
});

const adminConfigRoute = createRoute({
  getParentRoute: () => adminLayoutRoute,
  path: '/admin/config',
  component: AdminConfigPage,
});

const routeTree = rootRoute.addChildren([
  publicLayoutRoute.addChildren([indexRoute]),
  loginRoute,
  adminLayoutRoute.addChildren([adminIndexRoute, adminQuotesRoute, adminConfigRoute]),
]);

export const router = createRouter({ routeTree });

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router;
  }
}
