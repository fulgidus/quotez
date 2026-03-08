export function getCredentials(): { username: string; password: string } | null {
  const stored = sessionStorage.getItem('auth');
  if (!stored) return null;
  return JSON.parse(stored);
}

export function setCredentials(username: string, password: string): void {
  sessionStorage.setItem('auth', JSON.stringify({ username, password }));
}

export function clearCredentials(): void {
  sessionStorage.removeItem('auth');
}

export function getAuthHeader(): string | null {
  const creds = getCredentials();
  if (!creds) return null;
  return 'Basic ' + btoa(`${creds.username}:${creds.password}`);
}

export async function verifyCredentials(username: string, password: string): Promise<boolean> {
  const header = 'Basic ' + btoa(`${username}:${password}`);
  try {
    const res = await fetch('/api/status', { headers: { 'Authorization': header } });
    return res.status === 200;
  } catch {
    return false;
  }
}
