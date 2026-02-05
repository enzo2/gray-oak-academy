//Dark mode is controlled by the class 'dark' on the html element (along with sl-theme-dark for Shoelace components)
//This script toggles the dark mode class and stores the preference in localStorage
//For new visitors, the preference is set based on the user's system preference

function setDarkModeIcon(iconButton, isDarkMode) {
  if (!iconButton) return;
  iconButton.name = isDarkMode ? 'sun' : 'moon-stars';
}

window.toggleDarkMode = function() {
  const isDarkMode = document.documentElement.classList.contains('dark');
  const iconButton = document.querySelector('.dark-mode-toggle');

  if (isDarkMode) {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.remove('sl-theme-dark','wa-dark');  
    localStorage.theme = 'light';
  } else {
    document.documentElement.classList.add('dark');
    document.documentElement.classList.add('sl-theme-dark', 'wa-dark'); 
    localStorage.theme = 'dark';
  }

  setDarkModeIcon(iconButton, !isDarkMode);
}

function initializeDarkMode() {
  const iconButton = document.querySelector('.dark-mode-toggle');
  
  // Check if the user has set a preference for dark mode
  const shouldUseDark = localStorage.theme === 'dark' || (!('theme' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches);
  if (shouldUseDark) {
    document.documentElement.classList.add('dark');
    document.documentElement.classList.add('sl-theme-dark', 'wa-dark');
  } else {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.remove('sl-theme-dark', 'wa-dark');
  }

  setDarkModeIcon(iconButton, shouldUseDark);

  if (iconButton) {
    // Turbo cache restores DOM without event listeners; ensure we always rebind.
    iconButton.removeEventListener('click', window.toggleDarkMode);
    iconButton.addEventListener('click', window.toggleDarkMode);
  }
}

document.addEventListener('turbo:load', initializeDarkMode);
document.addEventListener('DOMContentLoaded', initializeDarkMode);
