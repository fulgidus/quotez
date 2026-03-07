import { useState, useEffect, useCallback } from 'react';
import { ZenMode } from './display-modes/ZenMode';
import { RichMode } from './display-modes/RichMode';
import { SimpleMode } from './display-modes/SimpleMode';
import { ModeSelector } from './ModeSelector';

export type DisplayMode = 'zen' | 'rich' | 'simple';

export function QuoteDisplay() {
  const [mode, setMode] = useState<DisplayMode>(() => {
    const savedMode = localStorage.getItem('display_mode');
    if (savedMode === 'zen' || savedMode === 'rich' || savedMode === 'simple') {
      return savedMode;
    }
    return 'zen';
  });
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

  const handleModeChange = (newMode: DisplayMode) => {
    setMode(newMode);
    localStorage.setItem('display_mode', newMode);
  };

  const renderMode = () => {
    switch (mode) {
      case 'zen':
        return (
          <ZenMode 
            quote={quote} 
            loading={loading} 
            error={error} 
            onNewQuote={fetchQuote} 
          />
        );
      case 'rich':
        return (
          <RichMode 
            quote={quote} 
            loading={loading} 
            error={error} 
            onNewQuote={fetchQuote} 
          />
        );
      case 'simple':
        return (
          <SimpleMode 
            quote={quote} 
            loading={loading} 
            error={error} 
            onNewQuote={fetchQuote} 
          />
        );
      default:
        return <div>Mode {mode} not implemented yet</div>;
    }
  };

  return (
    <div className="quote-display-container">
      <ModeSelector mode={mode} onModeChange={handleModeChange} />
      {renderMode()}
    </div>
  );
}
