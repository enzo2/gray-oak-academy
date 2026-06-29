# Gray Oak Academy

Gray Oak Academy is a teacher-directed, LLM-conducted learning platform, designed to realize the long-awaited 1-on-1 private AI tutor &mdash; locally, under your governance. There is no built-in curriculum or opaque engine: prompts are overridable and every lesson plan, learning resource, and student observation passes through human supervision. You rapidly build fully custom courses, with LLM-assisted planning and expansion, external resources, bespoke applets, and offline experiences, and your LLM of choice conducts the lessons under your ongoing supervision. Your agent can drive it too, but you log on to give final approvals.

➡️ See **[VISION.md](VISION.md)** for the full design rationale and how it addresses the crises in education.

## Features
- Teacher-directed, LLM-conducted learning platform, thoughtfully designed for human control
- AI-augmented, yet deliberate curriculum building: Quickly plan, research, and expand a full course according to your goals; take full manual control at any point
- Trusted personal agent access (e.g. OpenClaw, Hermes) via optional API + SKILL.md; teacher still gives final approvals
- Powerful LLM tutor: can create/run JavaScript applets, display web resources, save memories and observations, evaluate students
- Integrated multimodal LLM chat for teachers and students, with STT/TTS/auto-read, images & webcam, and "chalkboard" (canvas accessible by the LLM)
- Encourages away-from-keyboard: Reduce screen time with speech-only lessons, or go offline entirely with debrief-only lessons
- Longitudinal student model with atomic observations keeps a fluid view of student progress; teacher may veto observations
- Reports, observations, and memories feed forward, ensuring continuity
- Discuss student progress with the LLM in depth, or review progress reports manually
- Quick Lessons: Prepare and approve a one-off lesson in just a couple minutes

### Cool tech stuff
- Self-hostable with docker
- All system prompts can be customized (opinionated defaults included)
- Works with any OpenAI-compatible API (including local). OpenAI, OpenRouter, and xAI use Responses API. 
- API + token management: Preload multiple LLM APIs for teachers to choose from
- Auto model metadata fetching; actual cost tracking for OpenRouter and xAI
- Automated memory saving and semantic consolidation, with choice of embeddings model
- Applets can send results back to the chat
- Image gen support via OpenRouter
- If LLM supports raw audio input, it will be sent immediately, then transcribed in the background
- Markdown and KaTeX support
- In-app/local Python code execution environment
- App name can be customized via env variable
- Dark/Light mode
- Installable PWA

### Frameworks/Tooling
 - Rails 8, Ruby 4, Postgres 18
 - Turbo/Stimulus
 - Tailwind CSS
 - No npm, just importmaps

### Security
- Devise for authentication
- Superuser, Teacher and Student roles
- Teacher-scoped API tokens for AI agent access
- Rate limiting via rack-attack
- The default Docker setup serves plain HTTP, intended to run behind your own reverse proxy / TLS termination. See [Production](#production).
- Note: The LLM is permitted to auto-execute its own JavaScript within a sandboxed iframe. 

## Setup Instructions
- `git clone` the repository to your machine. 
- Docker is needed. (Note: If using Windows with WSL2 and Docker Desktop, clone into your WSL filesystem (e.g. \\wsl.localhost\Ubuntu), otherwise the app will be super slow.)
- Choose an OpenAI-compatible LLM API. See below sections 'Choosing an API' & 'Choosing LLMs'.
- Choose development (Devcontainer) or production (Docker) environment. If you're just trying out the app, production should be slightly easier to set up.

### Development: 
- Create `/.devcontainer/.env.development` following `/.devcontainer/.env.development.example`. 
- Open with VSCode, etc., and open the dev container. (If using Windows, use the WSL extension and 'Connect to WSL' first.)
- Run `bin/dev`. Visit http://localhost:3000. To access from other devices over the same LAN, visit https://your-machine-ip:3001 (note: you will get a self-signed root CA warning).

### Production:
- *Note: The default setup serves plain HTTP via Puma, fine for LAN use. One caveat: browsers require HTTPS (or localhost) for microphone/webcam input and PWA install, so to use those from other devices, front the app with something you likely already run — Tailscale, a Cloudflare tunnel, or a reverse proxy.*
- Create `/.env.production` following `.env.production.example`. Include a random 32-character `RAILS_MASTER_KEY`, and keep it secure. 
- Also create `/.env`: see `.env.example`. (This is for Postgres.)
- *As an alternative without .env files, e.g. for a Portainer stack deployment, `docker-compose-noenv.yml` is provided.*
- If proxying with SSL: in `config/environments/production.rb`, set `config.force_ssl = true` and `config.assume_ssl = true`, change the `default_url_options` protocols to `https`, and uncomment `config.hosts` with your domain to enable host authorization.
- Build and run with docker: `docker compose up -d`. Visit http://localhost:3001.
- For actual long-term use, retrieve the generated `/config/credentials/production.yml.enc` from the container's ephemeral filesystem and add it to your repository, so it will persist across restarts.
- Make sure to set strong, random `TEACHER_SIGNUP_CODE` and `STUDENT_SIGNUP_CODE` values — these codes are your registration gate.

### Choosing an API:
- Any OpenAI-compatible API is supported for chat/lessons. 
- Experimental support for ChatGPT account use via Codex: select `https://chatgpt.com/backend-api/codex/` as the API base URI
- Built-in support for OpenRouter makes it easy to: track actual costs, avoid token limits, display context window usage, try different providers/models easily. OpenRouter also supports BYOK and ZDR.
- Make sure to use an API that supports automated prompt caching.

### Choosing LLMs: 
- For the main chat/lesson LLM, choose a high-performing, adaptive-thinking model, or you may encounter issues related to tool use, generative applets, and lesson pacing. (This app is quite demanding of LLMs; however, avoid the largest frontier models, or chat will be too slow and expensive.) Model must support image input and function calling. Raw audio input is optional. A long context window is recommended. 
- Add a dedicated frontier thinking model for better performance on curriculum generation tasks, applets, and more. Model must support structured outputs. Image input not required.
- **Background agent runs (course research, resource proposal):** For these lengthy flows, API/model is configured by the superuser in App Settings, not per-teacher, as they require a very strong agentic model.
- For image generation, a frontier model is recommended. You can also enable 2-pass generation to allow a model to critique and regenerate its own output, for twice the cost.

## Getting Started
- Create a teacher account using the teacher signup code. 
- Become a superuser and access all functions/settings. Open a terminal inside the container, run `bin/rails console` and manually change your user_role, `User.first.role_superuser!`.)
- As a superuser, go to LLM API settings and set up shared tokens for OpenAI and OpenRouter. Go to App Settings and set up speech, Exa, and other settings.
- Go to your Settings > Preferences and set your API and models.
- To verify your setup and try the chat interface, go to LLM Chat. Try asking the LLM to generate an applet. (Note: for microphone input, you must be on localhost or HTTPS.)
- For agent access / SKILL.md, go to Settings > Agent Access.
- Create a course using the Course Manager, or by asking the LLM. Next, generate a course outline, and optionally run the outline research flow.
- You can then create lessons, followed by lesson plans. Finally, you can run the resource proposal agent on a plan.
- When the first lesson plan is ready, mark it as published. 
- Add a student account from the teacher's dashboard or using the student signup code. 
- Enroll the student in the course. The student can then go to their dashboard and start the lesson.

## Feature ideas:
- auto-compaction for providers besides OpenAI
- Address resource explosion (Resource archive & auto-organization)
- Non-digital resource availability/scheduling
- Scheduled lesson planning
- Additional agentic flows for curriculum planning 
- Non-lesson-based, graph-based course authoring & traversal (directed vs undirected)
- Improve student analytics
- MCP support
- Document uploads for curriculum building / local corpus search & linkage
- Refactor LLM tools into virtual CLI-style tools?
- Generative Python applets (pyodide iframe)
- Hide more advanced settings/features under a Power User setting
- Hotwire Native app; Mobile push notifications
- Speed up audio input with ffmpeg to reduce cost
- Note: Avoiding live/realtime APIs thus far due to risk of forced conversation and lower intelligence. May be suitable for AFK lessons.

## Backstory

*I'm a doctor, Jim, not a software engineer.* I started this as a personal project for homeschooling my son. I had dabbled in Rails over a decade prior in college, but my burgeoning penchant for making web apps abruptly disappeared within a week of starting med school. A few years into practicing medicine, LLMs made coding feasible again for me, and I found Rails still to be thriving (and great fun). In 2024, I started laying down the vision and schema for Gray Oak Academy in expectation that LLMs would advance enough to drive the app as tutors. So interestingly, this app's development spanned from the "autocomplete" era up to the present.

## Maintenance & Support

Gray Oak Academy is shared in the hope it's useful to other families. No support is provided, and self-hosting means you are responsible for your own deployment, security, and backups. Bug reports and high-quality PRs are welcome. If you find a security vulnerability, please email <lucas@grayoak.net> privately rather than opening a public issue. For commercial inquiries, see COMMERCIAL.md.

## License

Gray Oak Academy is source-available under the Elastic License 2.0 — free to self-host and modify. See LICENSE.md and COMMERCIAL.md.
