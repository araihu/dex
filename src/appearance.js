'use strict';

(() => {
  const root = document.documentElement;
  const themeSelect = document.querySelector('#araihu-theme');
  const modeButton = document.querySelector('.araihu-mode-button');
  const notice = document.querySelector('#araihu-storage-notice');
  if (!themeSelect || !modeButton) return;

  const safely = (operation, fallback) => {
    try {
      return operation();
    } catch {
      return fallback;
    }
  };
  const themes = new Set(Array.from(themeSelect.options, (option) => option.value));
  const validTheme = (theme) => typeof theme === 'string' && themes.has(theme);
  const fallbackTheme = themes.has('araihu') ? 'araihu' : themeSelect.options[0]?.value;
  const runtimeTheme = validTheme(window.__araihuDexDefaultTheme)
    ? window.__araihuDexDefaultTheme
    : fallbackTheme;
  const readConsent = () => safely(() => {
    const match = document.cookie
      .split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith('gt_storage='));
    const value = match?.slice('gt_storage='.length);
    return value === 'allowed' || value === 'denied' ? value : null;
  }, null);
  const consent = readConsent();
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
  const clearPreferences = () => {
    safely(() => localStorage.removeItem('theme'));
    safely(() => localStorage.removeItem('darkMode'));
  };

  applyTheme();
  applyDarkMode();
  if (notice) notice.hidden = consent !== null;
  if (consent === 'denied') clearPreferences();

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
    const cookieConfirmed = safely(() => {
      document.cookie = `gt_storage=${choice}; Path=/; Max-Age=15552000; SameSite=Lax`;
      return true;
    }, false) && readConsent() === choice;
    if (!cookieConfirmed) {
      storageAllowed = false;
      clearPreferences();
      notice.hidden = false;
      return;
    }
    const restoreFocus = notice.contains(document.activeElement);
    storageAllowed = choice === 'allowed';
    if (storageAllowed) persist();
    else clearPreferences();
    notice.hidden = true;
    if (restoreFocus) {
      const autofocus = document.querySelector('.dex-container [autofocus]');
      const fallback = Array.from(document.querySelectorAll(
        '.dex-container a[href], .dex-container button:not([disabled]), .dex-container input:not([type="hidden"]):not([disabled]), .dex-container select:not([disabled]), .dex-container textarea:not([disabled])',
      )).find((element) => element.getClientRects().length > 0);
      const target = autofocus?.getClientRects().length ? autofocus : fallback;
      target?.focus();
    }
  });
})();
