# Color Palette

Gray Oak Academy's official palette is built around restrained neutrals and muted greens. The intent is calm, academic, teacher-directed, and deferential rather than loud or brand-forward.

## Source Of Truth

- Base palette variables: `app/assets/stylesheets/application.css`
- Tailwind theme exposure: `app/assets/tailwind/application.css`
- App chrome defaults: `app/views/layouts/application.html.erb`
- Shared email palette: `app/views/layouts/mailer.html.erb`

## Active Palette

### Structure

- `stone`: primary neutral scale for surfaces, borders, and body text
- `paper`: warm companion neutral for softer surfaces
- `moss`: default brand and primary interactive color
- `forest`: deeper green companion for stronger anchors and selected states
- `success`: positive confirmation and completed states
- `warning`: caution, in-progress, and attention states
- `danger`: destructive and error states

### Core Anchors

- `stone-50`: `oklch(98.5% 0.001 106.423)`
- `stone-100`: `oklch(97% 0.001 106.424)`
- `stone-500`: `oklch(55.3% 0.013 58.071)`
- `stone-900`: `oklch(21.6% 0.006 56.043)`
- `neutral-0`: `#fefbf5`
- `neutral-1000`: `#15120d`

- `paper-100`: `#f7f2e8`
- `paper-500`: `#c7b69a`
- `paper-900`: `#5d4f3f`

- `moss-100`: `#eef2e1`
- `moss-300`: `#d4dbc0`
- `moss-500`: `#9ea76b`
- `moss-600`: `#7a8a53`
- `moss-700`: `#55673b`
- `moss-900`: `#1f3120`

- `forest-100`: `#d9e7de`
- `forest-500`: `#2b5b3f`
- `forest-900`: `#143829`

- `success-500`: `#5c8b2d`
- `warning-500`: `#c98a2e`
- `danger-500`: `#c0726b`

### Product-Level Accent Colors

- Browser and PWA light theme color: `#dbe5cc`
- Browser and PWA dark theme color: `#485340`

## Usage Rules

- Use `stone` for most surfaces, text, separators, and layout chrome.
- Use `paper` sparingly for warmer cards, inset surfaces, and reading areas that should feel less infrastructural than `stone`.
- Use `moss` for the app's default active states, branded links, and primary actions.
- Use `forest` when a deeper, steadier green is needed for hierarchy or selection, but not as the default replacement for `moss`.
- Use `success`, `warning`, and `danger` semantically, not decoratively.
- Avoid introducing raw Tailwind blues, slates, or arbitrary hex colors in app chrome when an existing semantic token fits.
- If a component needs a new color family, add it as a named token first instead of hardcoding one-off values.

## Current Tailwind/Shoelace Mapping

- Shoelace `primary` maps to `moss`
- Shoelace `neutral` maps to `stone`
- Shoelace `success`, `warning`, and `danger` map to the app semantic scales
- Tailwind exposes `paper`, `moss`, `forest`, `success`, `warning`, and `danger` for app-level utility classes
