//Dark mode is controlled by the class 'dark' on the html element (along with sl-theme-dark for Shoelace components)
//This script toggles the dark mode class and stores the preference in localStorage
//For new visitors, the preference is set based on the user's system preference

window.toggleDarkMode = function() {
  const isDarkMode = document.documentElement.classList.contains('dark');
  const iconButton = document.querySelector('.dark-mode-toggle');

  if (isDarkMode) {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.remove('sl-theme-dark');  
    localStorage.theme = 'light';
    iconButton.name = 'moon-stars';
  } else {
    document.documentElement.classList.add('dark');
    document.documentElement.classList.add('sl-theme-dark'); 
    localStorage.theme = 'dark';
    iconButton.name = 'sun';
  }
}

function initializeDarkMode() {
  const iconButton = document.querySelector('.dark-mode-toggle');
  
  // Check if the user has set a preference for dark mode
  if (localStorage.theme === 'dark' || (!('theme' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
    document.documentElement.classList.add('dark');
    document.documentElement.classList.add('sl-theme-dark');
    iconButton.name = 'sun';
  } else {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.remove('sl-theme-dark');
    iconButton.name = 'moon-stars';
  }
}

document.addEventListener('DOMContentLoaded', initializeDarkMode);