import { useEffect, useState } from 'react';
import '../../styles/rich.css';

interface RichModeProps {
  quote: string | null;
  loading: boolean;
  error: boolean;
  onNewQuote: () => void;
}

export function RichMode({ quote, loading, error, onNewQuote }: RichModeProps) {
  const [visible, setVisible] = useState(false);
  const [quoteCount, setQuoteCount] = useState(0);

  useEffect(() => {
    if (quote && !loading && !error) {
      setQuoteCount(prev => prev + 1);
      const timer = setTimeout(() => setVisible(true), 50);
      return () => clearTimeout(timer);
    } else {
      setVisible(false);
    }
  }, [quote, loading, error]);

  const renderContent = () => {
    if (loading && !quote) {
      return <div className="rich-status">Loading...</div>;
    }

    if (error) {
      return (
        <div className="rich-error">
          <p>Could not load quote</p>
          <button className="rich-button" onClick={onNewQuote}>Retry</button>
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
      <div className={`rich-card ${visible ? 'visible' : ''}`}>
        <div className="rich-counter" data-testid="quote-counter">
          Quote #{quoteCount}
        </div>
        <div className="rich-quote-wrapper">
          <div 
            className={`rich-quote ${visible ? 'typing' : ''}`} 
            data-testid="quote-text"
          >
            {text}
          </div>
          {author && (
            <div className={`rich-author ${visible ? 'visible' : ''}`}>
              — {author}
            </div>
          )}
        </div>
        <button 
          className="rich-button" 
          data-testid="new-quote-btn" 
          onClick={onNewQuote}
          disabled={loading}
        >
          New Quote
        </button>
      </div>
    );
  };

  return (
    <div className="rich-container">
      <div className="rich-bg" />
      {renderContent()}
    </div>
  );
}
