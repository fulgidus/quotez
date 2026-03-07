import '../../styles/simple.css';

interface SimpleModeProps {
  quote: string | null;
  loading: boolean;
  error: boolean;
  onNewQuote: () => void;
}

export function SimpleMode({ quote, loading, error, onNewQuote }: SimpleModeProps) {
  const renderContent = () => {
    if (loading && !quote) {
      return <div className="simple-status">Loading...</div>;
    }

    if (error) {
      return (
        <div className="simple-error">
          <p>Could not load quote</p>
          <button className="simple-button" onClick={onNewQuote}>Retry</button>
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
      <div className="simple-quote-wrapper">
        <div className="simple-quote" data-testid="quote-text">
          {text}
        </div>
        {author && (
          <div className="simple-author">
            — {author}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="simple-container">
      {renderContent()}
      {(!loading || quote) && !error && (
        <button 
          className="simple-button" 
          data-testid="new-quote-btn" 
          onClick={onNewQuote}
          disabled={loading}
        >
          New Quote
        </button>
      )}
    </div>
  );
}
