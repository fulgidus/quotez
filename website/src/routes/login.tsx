import { useState } from 'react';
import { useNavigate } from '@tanstack/react-router';
import { verifyCredentials, setCredentials } from '../lib/auth';

export function LoginPage() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const isValid = await verifyCredentials(username, password);
      if (isValid) {
        setCredentials(username, password);
        navigate({ to: '/admin' });
      } else {
        setError('Invalid credentials');
      }
    } catch (err) {
      setError('An error occurred during login');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      minHeight: '100vh',
      backgroundColor: 'var(--color-bg)'
    }}>
      <form
        data-testid="login-form"
        onSubmit={handleSubmit}
        style={{
          backgroundColor: 'var(--color-surface)',
          padding: 'var(--spacing-xl)',
          borderRadius: 'var(--radius)',
          border: '1px solid var(--color-border)',
          width: '100%',
          maxWidth: '400px',
          display: 'flex',
          flexDirection: 'column',
          gap: 'var(--spacing-md)'
        }}
      >
        <h1 style={{ textAlign: 'center', marginBottom: 'var(--spacing-md)' }}>Admin Login</h1>
        
        {error && (
          <div style={{
            color: '#ff6b6b',
            backgroundColor: 'rgba(255, 107, 107, 0.1)',
            padding: 'var(--spacing-sm)',
            borderRadius: 'var(--radius)',
            textAlign: 'center'
          }}>
            {error}
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          <label htmlFor="username" style={{ color: 'var(--color-text-muted)' }}>Username</label>
          <input
            id="username"
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
            style={{
              padding: 'var(--spacing-sm)',
              borderRadius: 'var(--radius)',
              border: '1px solid var(--color-border)',
              backgroundColor: 'var(--color-bg)',
              color: 'var(--color-text)',
              fontFamily: 'inherit'
            }}
          />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          <label htmlFor="password" style={{ color: 'var(--color-text-muted)' }}>Password</label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            style={{
              padding: 'var(--spacing-sm)',
              borderRadius: 'var(--radius)',
              border: '1px solid var(--color-border)',
              backgroundColor: 'var(--color-bg)',
              color: 'var(--color-text)',
              fontFamily: 'inherit'
            }}
          />
        </div>

        <button
          data-testid="login-submit"
          type="submit"
          disabled={loading}
          style={{
            marginTop: 'var(--spacing-md)',
            padding: 'var(--spacing-md)',
            backgroundColor: 'var(--color-accent)',
            color: '#fff',
            border: 'none',
            borderRadius: 'var(--radius)',
            cursor: loading ? 'not-allowed' : 'pointer',
            fontWeight: 'bold',
            opacity: loading ? 0.7 : 1,
            transition: 'background-color var(--transition)'
          }}
        >
          {loading ? 'Logging in...' : 'Login'}
        </button>
      </form>
    </div>
  );
}
