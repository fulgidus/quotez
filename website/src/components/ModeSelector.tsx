import { DisplayMode } from './QuoteDisplay';
import '../styles/mode-selector.css';

interface ModeSelectorProps {
  mode: DisplayMode;
  onModeChange: (mode: DisplayMode) => void;
}

export function ModeSelector({ mode, onModeChange }: ModeSelectorProps) {
  return (
    <div className="mode-selector" data-testid="mode-selector">
      <button
        className={`mode-btn ${mode === 'zen' ? 'active' : ''}`}
        data-testid="mode-btn-zen"
        onClick={() => onModeChange('zen')}
      >
        Zen
      </button>
      <button
        className={`mode-btn ${mode === 'rich' ? 'active' : ''}`}
        data-testid="mode-btn-rich"
        onClick={() => onModeChange('rich')}
      >
        Rich
      </button>
      <button
        className={`mode-btn ${mode === 'simple' ? 'active' : ''}`}
        data-testid="mode-btn-simple"
        onClick={() => onModeChange('simple')}
      >
        Simple
      </button>
    </div>
  );
}
