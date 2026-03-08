import { useEffect, useState } from 'react';
import { fetchStatus, triggerReload, toggleMaintenance } from '../../lib/api';

function formatUptime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${h}h ${m}m ${s}s`;
}

export function AdminPage() {
  const [statusData, setStatusData] = useState<{status: string, quotes: number, mode: string, uptime_seconds: number, polling_interval: number} | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadResult, setReloadResult] = useState<string | null>(null);

  const loadStatus = async () => {
    try {
      const data = await fetchStatus();
      setStatusData(data);
      setError(null);
    } catch (err: any) {
      setError(err.message || 'Failed to fetch status');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadStatus();
    const interval = setInterval(loadStatus, 10000);
    return () => clearInterval(interval);
  }, []);

  const handleReload = async () => {
    try {
      const res = await triggerReload();
      setReloadResult(`Reloaded ${res.quotes} quotes`);
      setTimeout(() => setReloadResult(null), 3000);
      loadStatus();
    } catch (err: any) {
      setReloadResult(`Error: ${err.message}`);
    }
  };

  const handleMaintenance = async () => {
    if (!statusData) return;
    try {
      await toggleMaintenance(statusData.status !== 'maintenance');
      loadStatus();
    } catch (err: any) {
      alert(`Failed to toggle maintenance: ${err.message}`);
    }
  };

  if (loading) {
    return <div style={{ color: 'var(--color-text-muted)' }}>Loading dashboard...</div>;
  }

  if (error) {
    return <div style={{ color: 'red' }}>Error: {error}</div>;
  }

  if (!statusData) return null;

  const isMaintenance = statusData.status === 'maintenance';

  return (
    <div>
      <h1 style={{ marginBottom: 'var(--spacing-lg)' }}>Dashboard</h1>
      
      <div 
        data-testid="status-card"
        style={{
          background: 'var(--color-surface)',
          border: '1px solid var(--color-border)',
          borderRadius: 'var(--radius)',
          padding: 'var(--spacing-lg)',
          marginBottom: 'var(--spacing-lg)',
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--spacing-md)'
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2 style={{ margin: 0, fontSize: '1.25rem' }}>System Status</h2>
          <span style={{
            background: isMaintenance ? '#f59e0b' : '#10b981',
            color: 'white',
            padding: '4px 8px',
            borderRadius: 'var(--radius)',
            fontSize: '0.875rem',
            fontWeight: 'bold',
            textTransform: 'uppercase'
          }}>
            {statusData.status}
          </span>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 'var(--spacing-md)' }}>
          <div>
            <div style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>Quotes</div>
            <div style={{ fontSize: '1.5rem', fontWeight: 'bold' }}>{statusData.quotes}</div>
          </div>
          <div>
            <div style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>Mode</div>
            <div style={{ fontSize: '1.5rem', fontWeight: 'bold', textTransform: 'capitalize' }}>{statusData.mode.replace(/-/g, ' ')}</div>
          </div>
          <div>
            <div style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>Uptime</div>
            <div style={{ fontSize: '1.5rem', fontWeight: 'bold' }}>{formatUptime(statusData.uptime_seconds)}</div>
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 'var(--spacing-md)', alignItems: 'center' }}>
        <button 
          data-testid="reload-btn"
          onClick={handleReload}
          style={{
            background: 'var(--color-accent)',
            color: 'white',
            border: 'none',
            padding: 'var(--spacing-sm) var(--spacing-md)',
            borderRadius: 'var(--radius)',
            cursor: 'pointer',
            fontWeight: 'bold'
          }}
        >
          Reload Quotes
        </button>
        
        <button 
          data-testid="maintenance-btn"
          onClick={handleMaintenance}
          style={{
            background: isMaintenance ? 'var(--color-surface)' : '#f59e0b',
            color: isMaintenance ? 'var(--color-text)' : 'white',
            border: '1px solid var(--color-border)',
            padding: 'var(--spacing-sm) var(--spacing-md)',
            borderRadius: 'var(--radius)',
            cursor: 'pointer',
            fontWeight: 'bold'
          }}
        >
          {isMaintenance ? 'Disable Maintenance' : 'Enable Maintenance'}
        </button>

        {reloadResult && (
          <span style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>
            {reloadResult}
          </span>
        )}
      </div>
    </div>
  );
}
