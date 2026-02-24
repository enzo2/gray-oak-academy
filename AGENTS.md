## Project Overview

Gray Oak Academy is a teacher-directed, LLM-conducted learning platform for 1-on-1 AI tutoring. Teachers create courses and lesson plans; students receive personalized tutoring via LLM with multimodal chat, generative applets, and progress tracking. See README for detailed explanation and vision.

To fully understand the app, read README.md, seeds.rb, and schema.rb. 

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

### Tech Stack
- Rails 8, Ruby 4, PostgreSQL with pgvector extension
- Turbo/Stimulus (Hotwire) for frontend interactivity
- Tailwind CSS 4 + Shoelace web components
- Importmaps (no npm/node_modules)
- Solid Queue, Solid Cable, Solid Cache for background jobs and real-time

### Core Models

**User Roles**: `student`, `admin` (teacher), `superuser`
- Students belong to a teacher (`teacher_id` foreign key)
- Teachers (`role_teacher?`) are admin or superuser
- Orphaned students (no teacher) cannot use LLM features

**Curriculum Structure**:
- `Course` → has many `Lesson` (ordered via acts_as_list)
- `Lesson` → has one `LessonPlan` (contains actual lesson content)
- `Enrollment` → links students to courses
- `LessonProgress` → tracks student progress through lessons

**LLM Integration**:
- `Conversation` → thread of `Message` objects
- `Completion` → logs API calls with token usage and costs
- `Llm` → model metadata (context length, capabilities)
- `Tool` → LLM function calling specs (JSON schema validated)
- `Prompt` → all system prompts are user-editable, retrieved by category

**Student Progress**:
- `Observation` → atomic academic observations (pending/approved/rejected)
- `Memory` → persistent student facts with vector embeddings for RAG
- `StudentReport` → generated reports per lesson/course
- `StudentFeedback` → student ratings of lessons
- "Journal" view - UI timeline of student's progress

### Key Services

- `OpenaiApiService` - LLM completions wrapper supporting any OpenAI Chat Completions—compatible API
- `OpenaiResponsesService` - LLM wrapper for the OpenAI Responses API
- Tool Services - Execute LLM tool calls
- `SpeechService` - STT/TTS handling
- `ImageGenerationService` - AI image generation (primarily gemini-3-pro-image)

### Prompt System

All prompts are stored in the `Prompt` model with categories. The system prompt hierarchy:
1. `base_system_prompt` - foundational principles
2. `teaching_principles` - teaching style and ethics
3. Task-specific prompt (e.g., `lesson_tutor_session`, `teacher_assistant`)
4. `generative_guidelines` - appended when generative UI is enabled

Teachers can customize any prompt category. System falls back to default (teacher_id: nil) if no custom prompt exists.

### Event/Notification System

Uses Rails 8.1's `ActiveSupport::EventReporter` with publish-subscribe pattern:
- Event types defined in `config/notifications.yml`
- Events auto-generated in `app/models/events/` from YAML
- `NotificationSubscriber` handles delivery (in-app + email)
- Fire events with `Rails.event.notify(Events::EventName.new(...))`

See `dev_info/EventReporter_guide.md` for adding new notification types.

### Frontend Patterns

- Stimulus controllers in `app/javascript/controllers/`
- Turbo Streams for real-time updates via Action Cable
- Shoelace components imported individually via CDN in `config/importmap.rb`
- KaTeX for math rendering

### API Configuration

LLM APIs are configured per-user in `Setting`:
- `llm_api_base_uri` - OpenAI-compatible endpoint
- `llm_model_name` - primary chat model
- `thinking_model_name` - frontier model for curriculum & applet generation
- OpenRouter has special support for cost tracking, context limits, image gen, LLM capability autopopulation

## Key Principles

- **No hard-coded prompts** - All prompts use the `Prompt` model with defaults in seeds.rb
- **Teacher control** - Teachers define curriculum, prompts, and values; LLM executes
- **Self-hostable** - Works with any OpenAI-compatible API including local LLMs

## Coding styles

- Fat models, thin controllers - Business logic in models, controllers stay light
- Avoid adding low-value tests that have no bearing on app functionality, are unlikely to break in the future, or are one-off checks

## Alignment

- If user intent is not clear, ask before implementing. 
- Avoid unnecessary backward compatibility when actively working on new features that haven't been committed yet.