## Project Overview

Gray Oak Academy is a teacher-directed, LLM-conducted learning platform for 1-on-1 AI tutoring. Teachers create courses and lesson plans; students receive personalized tutoring via LLM with multimodal chat, generative applets, and progress tracking. See README for detailed explanation and vision.

If changing anything that affects the user, read README.md in order to fully understand the app, and consider reading seeds.rb and schema.rb.

## Development Commands

```bash
# Start development server (uses devcontainer with SSL)
bin/dev
# Access at http://localhost:3000 / https://localhost:3001, or https://your-ip:3001 for LAN access

# Run all non-system tests
rails test

# Run a specific test file
rails test test/models/user_test.rb

# Run a specific test by name
rails test test/models/user_test.rb -n test_name

# Run system tests
rails test:system

# Database operations
rails db:migrate (always ask permission)
rails db:seed              # Seeds default prompts, tools, and app settings
rails db:seed:refresh_defaults # Replaces default prompts/tools from seeds.rb, preserving teacher prompts

# Linting
rubocop

# Security audits
brakeman
bundler-audit

# Full local CI (takes a while)
# Includes setup, rubocop, audits, brakeman, tests, system tests, seeds
bin/ci
```

- The dev server uses https. When using any browser tool to view the site locally, use https://localhost:3000.
- All tests require Postgres DB access (located in devcontainer stack). If the DB is not reachable, your terminal may have a network permissions restriction.

## Architecture

### Prompt System

See `seeds.rb`. 

### Event and Notification System

See `dev_info/EventReporter_guide.md` for adding new notification types.

### Frontend Patterns

- Stimulus controllers in `app/javascript/controllers/`
- Turbo Stream for real-time updates
- Components imported individually via CDN in `config/importmap.rb`
- Color guide in `dev_info/color_palette.md`

## Key Principles

- **No hard-coded prompts** - All prompts use the `Prompt` model with defaults in seeds.rb
- **Teacher control** - Teachers define curriculum, prompts, and values; LLM executes
- **Self-hostable** - Works with any OpenAI-compatible API including local LLMs

## Coding styles

- Fat models, thin controllers: business logic in models, controllers stay light
- Avoid adding low-value tests that have no bearing on app functionality (e.g. precise UI verbiage), are unlikely to break in the future, or are one-off checks

## Alignment

- If user intent is not clear, ask before implementing. 
- Do not stage changes unless asked.
- Avoid unnecessary backward compatibility when actively working on new features that haven't been committed and pushed yet.
