import typography from '@tailwindcss/typography';
import containerQueries from '@tailwindcss/container-queries';

/** @type {import('tailwindcss').Config} */
export default {
	darkMode: 'class',
	content: ['./src/**/*.{html,js,svelte,ts}'],
	theme: {
		extend: {
			// CRUZ BRAND PATCH -------------------------------------------------
			// Open WebUI ships no colour config, so every surface resolves to
			// stock Tailwind grey -- a neutral slate that reads as generic. The
			// whole UI is built on `gray-*`, so remapping that single ramp tints
			// the entire interface at once instead of patching components.
			//
			// The ramp is violet-tinted at the dark end to match the Cruz site's
			// near-black-with-a-blue-cast, and kept close to neutral at the light
			// end so light mode stays legible.
			colors: {
				// Light surfaces in this codebase come from hard-coded `bg-white`,
				// NOT from the gray ramp -- which is why tinting gray alone left
				// light mode looking like stock Open WebUI. Softening white and
				// black is what actually carries the brand into light mode.
				// Pure #ffffff reads as generic; a barely-there violet cast reads
				// as designed, while staying well inside contrast requirements.
				white: '#fcfbff',
				black: '#14121f',

				// Dark end anchored to the marketing site's real tokens:
				//   --bg    #050507   -> gray-950
				//   --white #E8E8F0   -> gray-100  (its primary text colour)
				// Note the site's base is essentially NEUTRAL black, not the
				// violet-tinted black I had assumed from screenshots. The violet
				// comes from accents and glow, not the surfaces.
				gray: {
					50: '#f7f7fa',
					100: '#e8e8f0',
					200: '#d4d4e0',
					300: '#b8b8c8',
					400: '#8e8ea0',
					500: '#6e6e80',
					600: '#4e4e60',
					700: '#303040',
					750: '#24242f',
					800: '#191922',
					850: '#101017',
					900: '#0a0a0f',
					950: '#050507'
				},

				// Exact site values: --violet and --violet-lt.
				cruz: {
					300: '#a99cf5',
					400: '#8b7bf0',
					500: '#7a6aec',
					600: '#6c5ce7',
					700: '#5a4bd0',
					800: '#4a3cb0'
				},

				// --gold, used on the site for award/accolade marks.
				gold: '#c9a961'
			},
			// -------------------------------------------------------- END PATCH
			typography: {
				DEFAULT: {
					css: {
						pre: false,
						code: false,
						'pre code': false,
						'code::before': false,
						'code::after': false
					}
				}
			},
			padding: {
				'safe-bottom': 'env(safe-area-inset-bottom)'
			},
			transitionProperty: {
				width: 'width'
			}
		}
	},
	plugins: [typography, containerQueries]
};
