'use strict';

(() => {
  const root = document.documentElement;
  const themeSelect = document.querySelector('#araihu-theme');
  const modeButton = document.querySelector('.araihu-mode-button');
  const notice = document.querySelector('#araihu-storage-notice');
  if (!themeSelect || !modeButton) return;

  const storageError = (error) => error instanceof DOMException && (
    error.name === 'SecurityError' || error.name === 'QuotaExceededError'
  );
  const safely = (operation, fallback) => {
    try {
      return operation();
    } catch (error) {
      if (!storageError(error)) throw error;
      return fallback;
    }
  };
  const themes = new Set(Array.from(themeSelect.options, (option) => option.value));
  const validTheme = (theme) => typeof theme === 'string' && themes.has(theme);
  const fallbackTheme = themes.has('araihu') ? 'araihu' : themeSelect.options[0]?.value;
  const runtimeTheme = validTheme(window.__araihuDexDefaultTheme)
    ? window.__araihuDexDefaultTheme
    : fallbackTheme;
  const consent = safely(() => {
    const match = document.cookie
      .split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith('gt_storage='));
    const value = match?.slice('gt_storage='.length);
    return value === 'allowed' || value === 'denied' ? value : null;
  }, null);
  const storedTheme = consent === 'allowed'
    ? safely(() => localStorage.getItem('theme'), null)
    : null;
  const storedDarkMode = consent === 'allowed'
    ? safely(() => localStorage.getItem('darkMode'), null)
    : null;
  let theme = validTheme(storedTheme) ? storedTheme : runtimeTheme;
  let darkMode = storedDarkMode === 'true' || storedDarkMode === 'false'
    ? storedDarkMode === 'true'
    : window.matchMedia('(prefers-color-scheme: dark)').matches;
  let storageAllowed = consent === 'allowed';

  const applyTheme = () => {
    root.dataset.theme = theme;
    themeSelect.value = theme;
  };
  const applyDarkMode = () => {
    root.classList.toggle('dark', darkMode);
    modeButton.setAttribute('aria-pressed', String(darkMode));
    modeButton.setAttribute('aria-label', darkMode ? 'Ativar modo claro' : 'Ativar modo escuro');
  };
  const persist = () => {
    if (!storageAllowed) return;
    safely(() => localStorage.setItem('theme', theme));
    safely(() => localStorage.setItem('darkMode', String(darkMode)));
  };

  applyTheme();
  applyDarkMode();
  if (notice) notice.hidden = consent !== null;
  if (consent === 'denied') {
    safely(() => localStorage.removeItem('theme'));
    safely(() => localStorage.removeItem('darkMode'));
  }

  themeSelect.addEventListener('change', () => {
    if (!validTheme(themeSelect.value)) return;
    theme = themeSelect.value;
    applyTheme();
    persist();
  });
  modeButton.addEventListener('click', () => {
    darkMode = !darkMode;
    applyDarkMode();
    persist();
  });
  notice?.addEventListener('click', (event) => {
    const choice = event.target.closest('[data-storage-choice]')?.dataset.storageChoice;
    if (choice !== 'allowed' && choice !== 'denied') return;
    safely(() => {
      document.cookie = `gt_storage=${choice}; Path=/; Max-Age=15552000; SameSite=Lax`;
    });
    storageAllowed = choice === 'allowed';
    if (storageAllowed) persist();
    else {
      safely(() => localStorage.removeItem('theme'));
      safely(() => localStorage.removeItem('darkMode'));
    }
    notice.hidden = true;
  });
})();
