import { useState, useEffect, useCallback } from 'react';
import { ZenMode } from './display-modes/ZenMode';

export type DisplayMode = 'zen' | 'rich' | 'simple';

interface QuoteDisplayProps {
  mode: DisplayMode;
}

export function QuoteDisplay({ mode }: QuoteDisplayProps) {
  const [quote, setQuote] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<boolean>(false);

  const fetchQuote = useCallback(async () => {
    setLoading(true);
    setError(false);
    try {
      const response = await fetch('/qotd');
      if (!response.ok) {
        throw new Error('Failed to fetch quote');
      }
      const text = await response.text();
      setQuote(text.trim());
    } catch (err) {
      console.error('Error fetching quote:', err);
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchQuote();
  }, [fetchQuote]);

  if (mode === 'zen') {
    return (
      <ZenMode 
        quote={quote} 
        loading={loading} 
        error={error} 
        onNewQuote={fetchQuote} 
      />
    );
  }

  return <div>Mode {mode} not implemented yet</div>;
}
