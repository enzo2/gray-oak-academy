// Attach the function to the window object to make it globally accessible
window.toggleDarkMode = function() {
  const isDarkMode = document.documentElement.classList.contains('dark');
  const iconButton = document.querySelector('.dark-mode-toggle');

  if (isDarkMode) {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.remove('sl-theme-dark');
    localStorage.theme = 'light';
    iconButton.name = 'moon-stars';
    console.log("light mode enabled");
  } else {
    document.documentElement.classList.add('dark');
    document.documentElement.classList.add('sl-theme-dark');
    localStorage.theme = 'dark';
    iconButton.name = 'sun';
    console.log("dark mode enabled");
  }
}

function initializeDarkMode() {
  const iconButton = document.querySelector('.dark-mode-toggle');
  
  if (localStorage.theme === 'dark' || (!('theme' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
    document.documentElement.classList.add('dark');
    document.documentElement.classList.add('dark');
    iconButton.name = 'sun';
    console.log("dark mode enabled");
  } else {
    document.documentElement.classList.remove('dark');
    document.documentElement.classList.remove('sl-theme-dark');
    iconButton.name = 'moon-stars';
    console.log("light mode enabled");
  }
}

document.addEventListener('DOMContentLoaded', initializeDarkMode);