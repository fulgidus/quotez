import { useState, useEffect } from 'react';
import { fetchQuotes, createQuote, updateQuote, deleteQuote } from '../lib/api';

type Quote = { id: number; text: string };

export function AdminQuotesPage() {
  const [quotes, setQuotes] = useState<Quote[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null);
  
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingQuote, setEditingQuote] = useState<Quote | null>(null);
  const [formText, setFormText] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    loadQuotes();
  }, []);

  const showToast = (message: string, type: 'success' | 'error') => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  };

  const loadQuotes = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await fetchQuotes();
      setQuotes(data);
    } catch (err: any) {
      setError(err.message || 'Failed to load quotes');
    } finally {
      setLoading(false);
    }
  };

  const handleAddClick = () => {
    setEditingQuote(null);
    setFormText('');
    setIsFormOpen(true);
  };

  const handleEditClick = (quote: Quote) => {
    setEditingQuote(quote);
    setFormText(quote.text);
    setIsFormOpen(true);
  };

  const handleDeleteClick = async (id: number) => {
    if (!window.confirm('Are you sure you want to delete this quote?')) return;
    
    try {
      await deleteQuote(id);
      setQuotes(quotes.filter(q => q.id !== id));
      showToast('Quote deleted successfully', 'success');
    } catch (err: any) {
      showToast(err.message || 'Failed to delete quote', 'error');
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formText.trim()) return;

    try {
      setIsSubmitting(true);
      if (editingQuote) {
        const updated = await updateQuote(editingQuote.id, formText);
        setQuotes(quotes.map(q => q.id === updated.id ? updated : q));
        showToast('Quote updated successfully', 'success');
      } else {
        const created = await createQuote(formText);
        setQuotes([...quotes, created]);
        showToast('Quote created successfully', 'success');
      }
      setIsFormOpen(false);
    } catch (err: any) {
      showToast(err.message || 'Failed to save quote', 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const truncate = (text: string, max: number) => {
    return text.length > max ? text.substring(0, max) + '...' : text;
  };

  return (
    <div style={{ position: 'relative' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--spacing-lg)' }}>
        <h1 style={{ margin: 0 }}>Quotes Management</h1>
        <button 
          data-testid="add-quote-btn"
          onClick={handleAddClick}
          style={{
            backgroundColor: 'var(--color-accent)',
            color: '#fff',
            border: 'none',
            padding: 'var(--spacing-sm) var(--spacing-md)',
            borderRadius: 'var(--radius)',
            cursor: 'pointer',
            fontWeight: 'bold',
            transition: 'background-color var(--transition)'
          }}
        >
          Add Quote
        </button>
      </div>

      {toast && (
        <div style={{
          position: 'fixed',
          top: 'var(--spacing-lg)',
          right: 'var(--spacing-lg)',
          padding: 'var(--spacing-md)',
          borderRadius: 'var(--radius)',
          backgroundColor: toast.type === 'success' ? '#2e7d32' : '#d32f2f',
          color: '#fff',
          zIndex: 1000,
          boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
        }}>
          {toast.message}
        </div>
      )}

      {isFormOpen && (
        <div style={{
          backgroundColor: 'var(--color-surface)',
          padding: 'var(--spacing-lg)',
          borderRadius: 'var(--radius)',
          marginBottom: 'var(--spacing-lg)',
          border: '1px solid var(--color-border)'
        }}>
          <h2 style={{ marginTop: 0, marginBottom: 'var(--spacing-md)' }}>
            {editingQuote ? 'Edit Quote' : 'Add New Quote'}
          </h2>
          <form onSubmit={handleSubmit}>
            <textarea
              data-testid="quote-textarea"
              value={formText}
              onChange={(e) => setFormText(e.target.value)}
              style={{
                width: '100%',
                minHeight: '100px',
                padding: 'var(--spacing-sm)',
                backgroundColor: 'var(--color-bg)',
                color: 'var(--color-text)',
                border: '1px solid var(--color-border)',
                borderRadius: 'var(--radius)',
                marginBottom: 'var(--spacing-md)',
                fontFamily: 'inherit',
                resize: 'vertical'
              }}
              placeholder="Enter quote text here..."
              required
            />
            <div style={{ display: 'flex', gap: 'var(--spacing-sm)', justifyContent: 'flex-end' }}>
              <button
                type="button"
                onClick={() => setIsFormOpen(false)}
                style={{
                  backgroundColor: 'transparent',
                  color: 'var(--color-text)',
                  border: '1px solid var(--color-border)',
                  padding: 'var(--spacing-sm) var(--spacing-md)',
                  borderRadius: 'var(--radius)',
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="submit"
                data-testid="quote-submit"
                disabled={isSubmitting}
                style={{
                  backgroundColor: 'var(--color-accent)',
                  color: '#fff',
                  border: 'none',
                  padding: 'var(--spacing-sm) var(--spacing-md)',
                  borderRadius: 'var(--radius)',
                  cursor: isSubmitting ? 'not-allowed' : 'pointer',
                  opacity: isSubmitting ? 0.7 : 1
                }}
              >
                {isSubmitting ? 'Saving...' : 'Save'}
              </button>
            </div>
          </form>
        </div>
      )}

      {loading ? (
        <div style={{ textAlign: 'center', padding: 'var(--spacing-xl)', color: 'var(--color-text-muted)' }}>
          Loading quotes...
        </div>
      ) : error ? (
        <div style={{ 
          backgroundColor: 'rgba(211, 47, 47, 0.1)', 
          color: '#ff5252', 
          padding: 'var(--spacing-md)', 
          borderRadius: 'var(--radius)',
          border: '1px solid rgba(211, 47, 47, 0.3)'
        }}>
          {error}
        </div>
      ) : quotes.length === 0 ? (
        <div style={{ 
          textAlign: 'center', 
          padding: 'var(--spacing-xl)', 
          backgroundColor: 'var(--color-surface)',
          borderRadius: 'var(--radius)',
          color: 'var(--color-text-muted)'
        }}>
          No quotes yet. Click "Add Quote" to create one.
        </div>
      ) : (
        <div data-testid="quotes-list" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--spacing-sm)' }}>
          {quotes.map(quote => (
            <div 
              key={quote.id} 
              data-testid={`quote-row-${quote.id}`}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: 'var(--spacing-md)',
                backgroundColor: 'var(--color-surface)',
                borderRadius: 'var(--radius)',
                border: '1px solid var(--color-border)'
              }}
            >
              <div style={{ flex: 1, marginRight: 'var(--spacing-md)', overflow: 'hidden' }}>
                <div style={{ 
                  fontSize: '0.8em', 
                  color: 'var(--color-text-muted)', 
                  marginBottom: '4px' 
                }}>
                  ID: {quote.id}
                </div>
                <div style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {truncate(quote.text, 80)}
                </div>
              </div>
              <div style={{ display: 'flex', gap: 'var(--spacing-sm)' }}>
                <button
                  onClick={() => handleEditClick(quote)}
                  style={{
                    backgroundColor: 'transparent',
                    color: 'var(--color-accent)',
                    border: '1px solid var(--color-accent)',
                    padding: '4px 12px',
                    borderRadius: 'var(--radius)',
                    cursor: 'pointer'
                  }}
                >
                  Edit
                </button>
                <button
                  onClick={() => handleDeleteClick(quote.id)}
                  style={{
                    backgroundColor: 'transparent',
                    color: '#ff5252',
                    border: '1px solid #ff5252',
                    padding: '4px 12px',
                    borderRadius: 'var(--radius)',
                    cursor: 'pointer'
                  }}
                >
                  Delete
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
