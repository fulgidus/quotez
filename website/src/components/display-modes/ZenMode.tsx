import { useEffect, useState } from 'react';
import '../../styles/zen.css';

interface ZenModeProps {
  quote: string | null;
  loading: boolean;
  error: boolean;
  onNewQuote: () => void;
}

export function ZenMode({ quote, loading, error, onNewQuote }: ZenModeProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (quote && !loading && !error) {
      // Small delay to ensure DOM is updated before applying transition class
      const timer = setTimeout(() => setVisible(true), 50);
      return () => clearTimeout(timer);
    } else {
      setVisible(false);
    }
  }, [quote, loading, error]);

  const renderContent = () => {
    if (loading && !quote) {
      return <div className="zen-status">Loading...</div>;
    }

    if (error) {
      return (
        <div className="zen-error">
          <p>Could not load quote</p>
          <button className="zen-button" onClick={onNewQuote}>Retry</button>
        </div>
      );
    }

    if (!quote) return null;

    let text = quote;
    let author = '';

    if (quote.includes(' — ')) {
      const parts = quote.split(' — ');
      author = parts.pop() || '';
      text = parts.join(' — ');
    } else if (quote.includes(' - ')) {
      const parts = quote.split(' - ');
      author = parts.pop() || '';
      text = parts.join(' - ');
    }

    return (
      <div className="zen-quote-wrapper">
        <div 
          className={`zen-quote ${visible ? 'visible' : ''}`} 
          data-testid="quote-text"
        >
          {text}
        </div>
        {author && (
          <div className="zen-author">
            — {author}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="zen-container">
      <div className="zen-bg" />
      <div className="zen-content">
        {renderContent()}
        
        <button 
          className="zen-button" 
          data-testid="new-quote-btn" 
          onClick={onNewQuote}
          disabled={loading}
        >
          New Quote
        </button>
      </div>
    </div>
  );
}
