import { useEffect, useState } from 'react';
import { fetchConfig, updateConfig } from '../../lib/api';

export function AdminConfigPage() {
  const [config, setConfig] = useState<{selection_mode: string, polling_interval: number, directories: string[]} | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<{message: string, type: 'success' | 'error'} | null>(null);

  const [mode, setMode] = useState('random');
  const [interval, setInterval] = useState(60);

  useEffect(() => {
    const loadConfig = async () => {
      try {
        const data = await fetchConfig();
        setConfig(data);
        setMode(data.selection_mode);
        setInterval(data.polling_interval);
        setError(null);
      } catch (err: any) {
        setError(err.message || 'Failed to fetch config');
      } finally {
        setLoading(false);
      }
    };
    loadConfig();
  }, []);

  const handleApply = async () => {
    try {
      await updateConfig({ selection_mode: mode, polling_interval: interval });
      setToast({ message: 'Configuration updated successfully', type: 'success' });
      setTimeout(() => setToast(null), 3000);
    } catch (err: any) {
      setToast({ message: `Failed to update config: ${err.message}`, type: 'error' });
    }
  };

  if (loading) {
    return <div style={{ color: 'var(--color-text-muted)' }}>Loading configuration...</div>;
  }

  if (error) {
    return <div style={{ color: 'red' }}>Error: {error}</div>;
  }

  if (!config) return null;

  return (
    <div>
      <h1 style={{ marginBottom: 'var(--spacing-lg)' }}>Configuration</h1>
      
      <div style={{
        background: 'var(--color-surface)',
        border: '1px solid var(--color-border)',
        borderRadius: 'var(--radius)',
        padding: 'var(--spacing-lg)',
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--spacing-lg)'
      }}>
        
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          <label style={{ fontWeight: 'bold' }}>Selection Mode</label>
          <select 
            data-testid="mode-select"
            value={mode}
            onChange={(e) => setMode(e.target.value)}
            style={{
              padding: 'var(--spacing-sm)',
              borderRadius: 'var(--radius)',
              border: '1px solid var(--color-border)',
              background: 'var(--color-bg)',
              color: 'var(--color-text)',
              width: '100%',
              maxWidth: '300px'
            }}
          >
            <option value="random">Random</option>
            <option value="sequential">Sequential</option>
            <option value="random-no-repeat">Random No Repeat</option>
            <option value="shuffle-cycle">Shuffle Cycle</option>
          </select>
          <span style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>
            How quotes are selected when requested.
          </span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          <label style={{ fontWeight: 'bold' }}>Polling Interval (seconds)</label>
          <input 
            type="number" 
            data-testid="interval-input"
            min="1"
            value={interval}
            onChange={(e) => setInterval(parseInt(e.target.value, 10) || 1)}
            style={{
              padding: 'var(--spacing-sm)',
              borderRadius: 'var(--radius)',
              border: '1px solid var(--color-border)',
              background: 'var(--color-bg)',
              color: 'var(--color-text)',
              width: '100%',
              maxWidth: '300px'
            }}
          />
          <span style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>
            How often to check directories for new or updated quotes.
          </span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          <label style={{ fontWeight: 'bold' }}>Directories</label>
          <ul 
            data-testid="directories-list"
            style={{
              margin: 0,
              padding: 'var(--spacing-md)',
              background: 'var(--color-bg)',
              border: '1px solid var(--color-border)',
              borderRadius: 'var(--radius)',
              listStyleType: 'none',
              display: 'flex',
              flexDirection: 'column',
              gap: 'var(--spacing-sm)'
            }}
          >
            {config.directories.map((dir, i) => (
              <li key={i} style={{ fontFamily: 'monospace', fontSize: '0.875rem' }}>{dir}</li>
            ))}
            {config.directories.length === 0 && (
              <li style={{ color: 'var(--color-text-muted)', fontStyle: 'italic' }}>No directories configured</li>
            )}
          </ul>
          <span style={{ color: 'var(--color-text-muted)', fontSize: '0.875rem' }}>
            Directories being monitored for quote files (read-only).
          </span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--spacing-md)', marginTop: 'var(--spacing-md)' }}>
          <button 
            data-testid="apply-btn"
            onClick={handleApply}
            style={{
              background: 'var(--color-accent)',
              color: 'white',
              border: 'none',
              padding: 'var(--spacing-sm) var(--spacing-lg)',
              borderRadius: 'var(--radius)',
              cursor: 'pointer',
              fontWeight: 'bold'
            }}
          >
            Apply Changes
          </button>

          {toast && (
            <span style={{ 
              color: toast.type === 'success' ? '#10b981' : '#ef4444',
              fontWeight: 'bold',
              fontSize: '0.875rem'
            }}>
              {toast.message}
            </span>
          )}
        </div>

      </div>
    </div>
  );
}
