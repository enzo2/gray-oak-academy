const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],

  darkMode: 'selector',

  theme: {

    extend: {
      colors:{
        //'yellow-custom1': '#f8bc72',
      },

      spacing:{
        '1/2screen':'50vh',
        '2/3screen':'66vh',
        '3/4screen':'75vh'
      }

    },
  
    fontFamily: { 
      //sans: ['"Merriweather Sans"', ...defaultTheme.fontFamily.sans], 
      //serif: ['"Playfair Display"', ...defaultTheme.fontFamily.serif] 
    }, 

    minHeight:{
      '0': '0',
      '1/4': '25%',
      '1/2': '50%',
      '3/4': '75%',
      '5/6': '83%',
      'full': '100%',
      '1/2screen':'50vh',
      '3/4screen': '75vh',
      'screen': '100vh',
      '500':'500px'
    },

    maxHeight: {
      '0': '0',
      '1/4': '25%',
      '1/2': '50%',
      '3/4': '75%',
      '5/6': '83%',
      'full': '100%',
      '5/6screen': '83vh',
      'screen': '100vh'
    },

  },


  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ],


}
