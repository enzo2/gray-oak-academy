const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/services/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,html}'
  ],

  darkMode: 'selector', 

  theme: {
    extend: {

      spacing:{
        '1/2screen':'50vh',
        '2/3screen':'66vh',
        '3/4screen':'75vh',
        '5/6screen':'83vh',
        'screen':'100vh'
      }

    },
  
    fontFamily: { 
      sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      //sans: ['"Merriweather Sans"', ...defaultTheme.fontFamily.sans], 
      //serif: ['"Playfair Display"', ...defaultTheme.fontFamily.serif] 
    }

  },

  plugins: [
    require("@tailwindcss/forms"),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ]
}
