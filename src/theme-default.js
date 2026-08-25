window.__araihuDexDefaultTheme = "__ARAIHU_DEX_DEFAULT_THEME__";
window.__araihuDexThemeKeys = __ARAIHU_DEX_THEME_KEYS__;
(() => {
  const root = document.documentElement;
  const safely = (operation, fallback) => {
    try {
      return operation();
    } catch {
      return fallback;
    }
  };
  const themes = new Set(window.__araihuDexThemeKeys);
  const defaultTheme = themes.has(window.__araihuDexDefaultTheme)
    ? window.__araihuDexDefaultTheme
    : 'araihu';
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
  const theme = themes.has(storedTheme) ? storedTheme : defaultTheme;
  const darkMode = storedDarkMode === 'true' || storedDarkMode === 'false'
    ? storedDarkMode === 'true'
    : safely(() => matchMedia('(prefers-color-scheme: dark)').matches, false);
  root.dataset.theme = theme;
  root.classList.toggle('dark', darkMode);
})();
