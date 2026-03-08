import { getAuthHeader } from './auth';

async function apiFetch(path: string, options?: RequestInit): Promise<Response> {
  const auth = getAuthHeader();
  const res = await fetch(path, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(auth ? { 'Authorization': auth } : {}),
      ...options?.headers,
    },
  });
  if (!res.ok) throw new Error(`API error ${res.status}: ${await res.text()}`);
  return res;
}

export async function fetchQuotes(): Promise<Array<{id: number, text: string}>> {
  const res = await apiFetch('/api/quotes');
  const data = await res.json();
  return data.quotes;
}

export async function createQuote(text: string): Promise<{id: number, text: string}> {
  const res = await apiFetch('/api/quotes', {
    method: 'POST',
    body: JSON.stringify({ text }),
  });
  return res.json();
}

export async function updateQuote(id: number, text: string): Promise<{id: number, text: string}> {
  const res = await apiFetch(`/api/quotes/${id}`, {
    method: 'PUT',
    body: JSON.stringify({ text }),
  });
  return res.json();
}

export async function deleteQuote(id: number): Promise<void> {
  await apiFetch(`/api/quotes/${id}`, {
    method: 'DELETE',
  });
}

export async function fetchStatus(): Promise<{status: string, quotes: number, mode: string, uptime_seconds: number, polling_interval: number}> {
  const res = await apiFetch('/api/status');
  return res.json();
}

export async function fetchConfig(): Promise<{selection_mode: string, polling_interval: number, directories: string[]}> {
  const res = await apiFetch('/api/config');
  return res.json();
}

export async function updateConfig(changes: {selection_mode?: string, polling_interval?: number}): Promise<void> {
  await apiFetch('/api/config', {
    method: 'PATCH',
    body: JSON.stringify(changes),
  });
}

export async function triggerReload(): Promise<{status: string, quotes: number}> {
  const res = await apiFetch('/api/reload', {
    method: 'POST',
  });
  return res.json();
}

export async function toggleMaintenance(enabled: boolean): Promise<void> {
  await apiFetch('/api/maintenance', {
    method: 'POST',
    body: JSON.stringify({ enabled }),
  });
}
