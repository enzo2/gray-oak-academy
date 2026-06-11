# Gray Oak Academy

## Background and Purpose
Gray Oak Academy is a teacher-directed, LLM-conducted learning platform, carefully designed to realize a rather old idea: that the future of education is 1-on-1 private tutoring conducted by AI. This app enables anyone, professor or parent, to easily build fully custom courses for an LLM to teach, incorporating external resources, generative applets, and offline experiences. Lesson plans are carried out by an LLM of choice, with teacher-supervised continuity. It addresses numerous emerging problems in education:

* **Superiority of 1:1 Tutoring**: [Some say by a lot, some say by a little](https://scholar.google.com/scholar?hl=en&q=2+sigma+problem), but most would agree that private tutoring is the gold standard for learning. Since ancient times, it has usually taken the form of hired tutors or home/parental teaching. The idea that AI could enable universal private tutoring has been a [science fiction tale](https://archive.org/details/Fantasy_Science_Fiction_v006n02_1954-02/page/n125/mode/2up) for decades ("The Fun They Had", Asimov, 1951). Now, it *should* be possible... yet, implementing a true end-to-end LLM tutor is not trivial, to say the least. Slapping a "Tutor Mode" button on standard LLM chat only works for highly motivated students who know roughly what they need to learn, and even that is usually in the context of existing coursework. More advanced solutions involve tradeoffs around alignment, curriculum, and disruptive potential. Purely agentic solutions ("OpenClaw, teach my kid, make no mistakes") are for a limited audience. 

  *Solution*: Teacher-directed, LLM-conducted—in other words, plan and execute. Steer the LLM tutor with a highly configurable and observable wrapper, including transparent prompt, curriculum, and resource management. Guide it with what to teach, how to do it, whom it's teaching, what resources are available, and when to stop. Do all this efficiently with LLM assistance. Remain in supervision and continuously review extracted observations, memories, and reports about the student.

* **The Role of Teachers**: Some suppose that teachers should take on a non-academic role in an LLM-tutored world. With a superintelligent tutor for every child, what's left to do? 

  *Solution*: Intelligence has been commoditized, but teachers remain invaluable for reasons of responsibility, authority, judgment, and inspiration. The supervising teacher (or parent) is the individual who has authority to define the LLM's prompts and curriculum. That's particularly important as we see that LLM superintelligence does *not* always translate into alignment or good taste. But more than just wrangling LLMs, now the teacher can have more time to bring beauty, delight, and contentment into the lives of youth: to spend time seeking out learning resources (both digital and physical), incorporating more memorable experiences, mentoring individual students, and helping them to gain not only knowledge, but wisdom. *This app explicitly requires a fully engaged supervising teacher. For example, LLM observations of the student must be approved or rejected before they feed forward.*

* **Cheating, Apathy and Boredom**: "Do my homework for me" is the status quo of the GPT era, now widely considered a crisis in education. The underlying problem is that school can be long, repetitive, and impersonal, with homework as insult upon injury! The answer has been to promote LLMs as resourceful study assistants—an incremental improvement.

  *Solution*: By deliberately teaching *through* the LLM, the potential for academic dishonesty or wasted effort is excluded. The need for homework and exams will diminish, as practice and evaluation are folded into lessons, allowing more time for exploratory learning and meaningful application. As a private tutor, the LLM will identify a struggling or disinterested student and find ways to hold their attention (including just-in-time applets). After lessons, students will feel satisfied that their new knowledge is practical and useful.

* **Local Control**: To put it mildly, many parents will not be happy to hand their child to a centralized AI system. For K-12, local control must be at the core of an AI tutor, with respect both to the curriculum and the API/LLM used. 

  *Solution*: Gray Oak Academy does not contain a built-in curriculum or knowledge graph. It has an opinionated default set of teacher-editable prompts defining the methodology, principles, and values for the LLM to follow. Course generation includes an optional agentic step that requires the teacher to answer questions about the intended approach. The combination of prompt transparency and lesson plan control provides assurance to users (whether homeschooling parents, private schools, or school districts) that potentially overfitted LLMs are not left to their own devices or restricted to a corporate worldview. Both API and models are teacher-configurable with any OpenAI-compatible API (with special support for OpenRouter), making it easy to try different models and providers.

* **Ensloppification**: AI image, video, and audio generation can undoubtedly be used to create memorable educational material. This can be helpful, but it also leads to a proliferation of inaccurate, superficial, even mind-numbing content, when primary sources should be used instead. 

  *Solution*: The app's agent can quickly discover internet resources, but the supervising teacher must approve them, as well as add their own non-internet resources. Image generation is available to the LLM, but it's instructed how to use it responsibly. 

* **Screen Time**:  The LLM can and should be bridged into the real world by linking resources like books, tools, demonstrations, even human resources. However, some lessons are better taught away from the computer, or through casual conversation. Some activities should not be tutored at all.

  *Solution*: Voice-only lessons allow learning in any setting, like a "walk-and-talk", lab or workshop. Going further, "offline" lessons are encouraged, where the student is given an activity and debriefed afterward. (You could even make an entire course of offline workshops, like reading a book, drawing, or a series of projects.)

Importantly, the system should negate the arguments implied in [Isaac Asimov's short story](https://archive.org/details/Fantasy_Science_Fiction_v006n02_1954-02/page/n125/mode/2up), namely that an AI homeschool tutor would be boring, unadaptable, and overly reliant on screen time and tedious homework rather than tactile resources and social experiences. This could still be a problem in the absence of human teacher. Therefore, as with traditional home– or small–group schooling, the supervisory teacher or parent remains responsible for keeping the student engaged and inspired by supplying a broad set of resources and experiences, monitoring progress, and adjusting the curriculum and prompts. If not, Asimov will be vindicated. 

## Features
- Teacher-directed, LLM-conducted learning platform, thoughtfully designed for human control
- AI-augmented, yet deliberate curriculum building: Quickly plan, research, and expand a full course according to your goals; take full manual control at any point in the process
- Quick Lessons: Prepare and approve a one-off lesson in just a couple minutes
- Powerful LLM tutor: can create/run JavaScript applets, display web resources, save memories and observations, evaluate students
- Integrated multimodal LLM chat for teachers and students, with STT/TTS/auto-read, images & webcam, and "chalkboard" (canvas accessible by the LLM)
- Trusted personal agent access (e.g. OpenClaw, Hermes) via optional API + SKILL.md; teacher still gives final approvals
- Encourages away-from-keyboard: Reduce screen time with speech-only lessons, or go offline entirely with debrief-only lessons
- Longitudinal student model with atomic observations keeps a fluid view of student progress; teacher may veto observations
- Reports, observations, and memories feed forward, ensuring continuity
- Discuss student progress with the LLM in depth, or review progress reports manually

### Cool tech stuff
- Self-hostable with docker
- All system prompts can be customized (opinionated defaults included)
- Works with any OpenAI-compatible API (including local). OpenAI, OpenRouter, and xAI use Responses API. 
- Image gen model support via OpenRouter
- API + token management: Preload multiple LLM APIs for teachers to choose from
- Auto model metadata fetching; actual cost tracking for OpenRouter and xAI
- Automated memory saving and semantic consolidation, with choice of embeddings model
- If LLM supports raw audio input, it will be sent immediately, then transcribed in the background
- Markdown and KaTeX support
- In-app Python code execution tool
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
- For security, not designed for hosting publicly by default. You will need to secure the app yourself by adding a reverse proxy, modifying the Dockerfile, production.rb, etc. 
- Teacher-scoped API tokens for AI agent access
- Note: The LLM is permitted to auto-execute its own JavaScript within a sandboxed iframe. 

## Setup Instructions
- `git clone` the repository to your machine. 
- Docker is needed. (Note: If using Windows with WSL2 and Docker Desktop, clone into your WSL filesystem (e.g. \\wsl.localhost\Ubuntu), otherwise the app will be super slow.)
- Choose an OpenAI-compatible LLM API. See below sections 'Choosing an API & LLM'.
- Choose a development (Devcontainer) or production (Docker) environment. If you're just trying out the app, production should be slightly easier to set up. (Exception: If you want to try speech input using your phone over the same LAN, use Devcontainer since it sets up a self-signed SSL certificate that you'll need.)

### Development: 
- Create `/.devcontainer/.env.development` following `/.devcontainer/.env.development.example`. 
- Open with VSCode, etc., and open the dev container. (If using Windows, use the WSL extension and 'Connect to WSL' first.)
- Run `rails server`. Visit http://localhost:3000. To access from other devices over the same LAN, visit https://your-machine-ip:3001 (note: you will get a self-signed root CA warning).

### Production:
- *Note: The default setup is not secure. It just runs the Puma server. The minimum option for serving publicly would be to enable Thruster, Rails' basic proxy with Let's Encrypt support, in the Dockerfile. You'll also need to adjust SSL settings in `/config/production.rb`. Please refer to Rails and Thruster documentation.*
- Create `/.env.production` following `.env.production.example`. Include a random 32-character `RAILS_MASTER_KEY`, and keep it secure. 
- OpenAI OAuth uses the built-in public Codex client id (`app_EMoamEEZ73f0CkXaXp7hrann`) with device authorization. No custom OAuth client configuration is currently supported.
- Also create `/.env`: see `.env.example`. (This is for Postgres.)
- *As an alternative without .env files, e.g. for a Portainer stack deployment, `docker-compose-noenv.yml` is provided.*
- Build and run with docker: `docker compose up -d`. Visit http://localhost:3001.
- For actual production use, retrieve the generated `/config/credentials/production.yml.enc` from the container's ephemeral filesystem and add it to your repository, so it will persist across restarts.

### Choosing an API:
- Any OpenAI-compatible API is supported for chat/lessons. 
- OpenAI provider supports optional OAuth credentialing in user settings for ChatGPT Codex Responses usage (select `https://chatgpt.com/backend-api/codex/` as API base URI).
- Built-in support for OpenRouter makes it easy to: track actual costs, avoid token limits, display context window usage, try different providers/models easily. OpenRouter also supports BYOK and ZDR.
- Make sure to use an API that supports automated prompt caching.
- For background agent runs during curriculum design, OpenAI currently works best, and Exa is required for web search.

### Choosing LLMs: 
- For the main chat/lesson LLM, choose a high-performing, adaptive-thinking model, or you may encounter issues related to tool use, generative applets, and lesson pacing. (This app is quite demanding of LLMs; however, avoid the largest frontier models, or chat will be too slow and expensive.) Model must support image input and function calling. Raw audio input is optional. A long context window is recommended. 
- Add a dedicated frontier thinking model for better performance on curriculum generation tasks, applets, and more. Model must support structured outputs.
- For image generation, gemini-3-pro-image or better is recommended. You can also enable 2-pass generation to allow a model to critique and regenerate its own output, for twice the cost.

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
- Non-digital resource availability/planning
- Additional agentic flows for curriculum planning 
- Improve student analytics
- MCP support
- Document uploads for curriculum building / local corpus search & linkage
- Refactor LLM tools into virtual CLI-style tools?
- Generative Python applets (pyodide iframe)
- Non-lesson-based, graph-based course option (directed graph creation and traversal)
- Hide more advanced settings/features under a Power User setting
- Speed up audio input with ffmpeg to reduce cost
- Avoiding live/realtime APIs thus far due to risk of forced conversation and lower intelligence. May be suitable for AFK lessons.
- Hotwire Native app; Mobile push notifications

## About the Creator

*I'm a doctor, Jim, not a software engineer.* I started this as a personal project for homeschooling my son. I had dabbled in Rails over a decade prior in college, but my burgeoning penchant for making web apps abruptly disappeared within a week of starting med school. A few years into practicing medicine, LLMs made coding feasible again for me, and I found Rails still to be thriving (and great fun). In 2024, I started laying down the vision and schema for Gray Oak Academy, but in early 2025, LLMs were still not capable of driving it. Knowing this would soon change, I pressed on and decided to fully realize the concept over the next year. The app is therefore a blend of LLM pair-programming and vibe-coding (and hopefully bears the artisanal aura of pre-2026 software).

## License

Gray Oak Academy is source-available under the Elastic License 2.0 — free to self-host and modify. See LICENSE.md and COMMERCIAL.md.
