# Gray Oak Academy

## Background and Purpose
Gray Oak Academy is a teacher-directed, LLM-conducted learning platform, designed to realize the rather old idea that the future of education is 1-on-1 private tutoring conducted by AI. This app allows anyone to easily build lesson plans or entire courses for an LLM to teach, incorporating learning resources and generative applets, and executing those lesson plans using any LLM. It addresses numerous emerging problems in education:

* **Superiority of 1:1 Tutoring**: [Some say by a lot, some say by a little](https://scholar.google.com/scholar?hl=en&q=2+sigma+problem), but most would agree that private tutoring is the best form of education, and LLMs can do it. Yet, implementing a true LLM tutor is not trivial. Slapping a "Tutor Mode" button onto a generic LLM chat only works for highly motivated students who know what they need to learn. 

  *Solution*: A flexible, highly configurable, and observable wrapper around LLM tutoring with prompt and curriculum management, lesson resources, multimodal chat, generative applets, and student progress tracking. Tell the LLM what to teach, how to do it, who it's teaching, what resources are available, and when to stop. Then, review extracted observations, memories, and reports about the student.

* **Cheating, Apathy and Boredom**: "Do my homework for me" is the status quo of the GPT era, now widely considered a crisis in education. The underlying problem is that school can be long, repetitive, impersonal&mdash;and homework is insult upon injury. The answer has been to promote LLMs as study assistants—an incremental improvement.

  *Solution*: By deliberately teaching *through* the LLM, the potential for academic dishonesty or wasted effort is excluded. The need for homework and exams will diminish, as practice and evaluation are folded into lessons, allowing more time for exploratory learning and meaningful application. Like a private tutor, the LLM will identify a struggling or disinterested student and find ways to hold their attention. After lessons, students will feel satisfied that their new knowledge is practical and useful.

* **Local Curriculum Control**: To put it mildly, many parents will not be happy to hand their child to a centralized AI system. For K-12, complete local control must be at the core of an AI tutor.

  *Solution*: Gray Oak Academy does not contain a built-in curriculum or knowledge graph. It has an opinionated default set of teacher-editable prompts defining the methodology, principles, and values for the LLM to follow. The combination of prompt transparency and lesson plan control provides assurance to users (whether homeschooling parents, private schools, or school districts) that overfitted LLMs are not left to their own devices to generate a curriculum out of a Silicon Valley&ndash;approved worldview. 

* **The Role of Teachers**: Some suppose that teachers should take on a non-academic role in an LLM-tutored world. With a superintelligent tutor for every child, what's left to do? 

  *Solution*: Intelligence has been commoditized, but teachers remain invaluable. The supervising teacher (or parent) is the individual who has authority to define the LLM's prompts and curriculum. But now, he or she has more time to bring beauty, delight, and contentment into the lives of youth however they see fit: to spend time seeking out learning resources (both digital and physical), incorporating more memorable experiences, mentoring individual students and helping them to gain not only knowledge, but wisdom. *This app explicitly requires a fully engaged supervising teacher.*

* **Ensloppification**: AI image, video, and audio generation can undoubtedly be used to create memorable educational material. This can be helpful, but it also leads to a proliferation of inaccurate, superficial, even mind-numbing content, when primary sources should be used instead. 

  *Solution*: The supervising teacher is responsible for adding appropriate media as resources. Image generation is available to the LLM, but it's instructed how to use it responsibly.

* **Screen Time**:  The LLM can and should be bridged into the real world by linking resources like tools, demonstrations, even human resources. However, some lessons are better taught away from the computer, or through casual conversation. Some activities should not be tutored at all.

  *Solution*: Raw audio input, STT, and TTS are combined to enable voice-only lessons without the high cost of realtime models. This enables learning in any setting, like "walk-and-talk" or workshops. Going further, "offline" lessons are encouraged, where the student is given an activity and debriefed afterward.

* **Vendor Lock-in**: LLMs are constantly changing in intelligence, personality, and relevant traits like sycophancy. It should be easy to switch models. In addition, for privacy, Zero Data Retention (ZDR) is needed.

  *Solution*: Both the API and models are fully user-configurable. Any OpenAI-compatible API can be used, with special support for OpenRouter, making it easy to try different models, providers, and configure ZDR. 

Importantly, the system should negate the arguments made in Isaac Asimov's 1951 short story ["The Fun They Had"](http://visual-memory.co.uk/daniel/funtheyhad.html), namely that an AI homeschool tutor would be boring, unadaptable, and overly reliant on screen time and tedious homework rather than tactile resources and social experiences. This could still be a problem in the absence of human teacher. Therefore, as with traditional home&ndash; or small&ndash;group schooling, the supervisory teacher or parent remains responsible for keeping the student engaged and inspired by supplying a broad set of resources and experiences, monitoring progress, and adjusting the curriculum and prompts. If not, Asimov will be vindicated. 

*Notice: I'm a doctor, Jim, not a software engineer.* I started this as a personal project for homeschooling. It's a prototype.

## Features
- Self-hostable with docker
- Works with any OpenAI-compatible API (including local)
- Highly configurable LLM tutoring: design your own curriculum with Courses, Lessons, Resources, Applets
- Rapid yet deliberate curriculum planning: Use a frontier LLM to quickly generate a full set of lessons according to your goals, then finalize lessons manually or with LLM assistance
- Integrated multimodal LLM chat for teachers and students, with images, STT/TTS/auto-read (no need for costly realtime models), and "chalkboard" (multipurpose frame accessible by the LLM)
- LLM can create/run Javascript applets, display files and URLs, finish lessons, save memories, and generate student reports
- Longitudinal student model with atomic observations keeps a fluid view of student progress
- Reports, observations, and memories feed forward, ensuring continuity and personalization
- Reduce screen time with speech-only lessons, or go offline entirely with debrief-only lessons

### More cool stuff
- All system prompts can be customized (opinionated defaults included)
- OpenRouter optimized (automated context limit tracking, actual cost tracking, LLM feature detection, image gen model support)
- API and token management: Preload multiple LLM APIs for teachers to choose from
- Automated memory saving and semantic consolidation
- Main LLM can query the frontier LLM at its discretion
- If LLM supports raw audio input, it will be sent immediately, then transcribed in the background
- Markdown and KaTeX support
- Python code execution tool via [https://github.com/khoj-ai/terrarium](URL)
- App name can be customized via env variable
- Dark/Light mode
- Installable PWA

### Frameworks/Tooling
 - Rails 8.0, Ruby 3.4, Postgres
 - Turbo/Stimulus
 - Tailwind CSS + Shoelace components
 - No npm, just importmaps
 - OpenAI-compatible API support (tested with OpenRouter, OpenAI, Gemini, and LM Studio)

### Security
- Devise for authentication
- Superuser, Teacher and Student roles
- For security, not designed for hosting publically by default. You will need to secure the app yourself by adding a reverse proxy, modifying the Dockerfile, production.rb, etc. 
- Note: The LLM is permitted to auto-execute its own javascript within a sandboxed iframe. 

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
- *Note: The default setup is not secure. It just runs the Puma server. The minimum option for serving publically would be to enable Thruster, Rails' basic proxy with Let's Encrypt support, in the Dockerfile. You'll also need to adjust SSL settings in `/config/production.rb`. Please refer to Rails and Thruster documentation.*
- Create `/.env.production` following `.env.production.example`. Include a random 32-character `RAILS_MASTER_KEY`, and keep it secure. 
- Also create `/.env`: see `.env.example`. (This is for Postgres.)
- *As an alternative without .env files, e.g. for a Portainer stack deployment, `docker-compose-noenv.yml` is provided.*
- Build and run with docker: `docker compose up -d`. Visit http://localhost:3001.
- For actual production use, retrieve the generated `/config/credentials/production.yml.enc` from the container's ephemeral filesystem and add it to your repository, so it will persist across restarts.

### Choosing an API:
- Any OpenAI-compatible API is supported. 
- Built-in support for OpenRouter makes it easy to: track actual costs, avoid token limits, display context window usage, try different providers/models easily. They also allow BYOK.
- Gemini API's OpenAI compatibility endpoint is a good option with free tier, raw audio support, and long context window models.
- For heavy users, providers supporting automated prompt caching may reduce cost.

### Choosing LLMs: 
- For the main chat/lesson LLM: model must support images and function calling. Audio input is optional. A long context window is recommended. For speed and cost, use a non-thinking or adaptive-thinking model. You must use a fairly intelligent model, or you may encounter issues related to tool use, generative applets, and lesson pacing. (This app is quite demanding of LLMs.) 
- Add a dedicated thinking model for better performance on curriculum generation tasks, applets, or anything else the main model wants to delegate. Model must support structured outputs. It should be a frontier, large-sized model. (Even some flagship models may not be good enough!)
- For image generation, the only suitable model thus far is gemini-3-pro-image. To further improve factual/textual accuracy, you can enable 2-pass generation to allow the model to critique and regenerate its own output.

## Getting Started
- Create a teacher account using the teacher signup code. (To become a superuser and access all functions, manually change your user_role from the console, `User.first.role_superuser!`.)
- Go to Settings > Preferences and set your API, token and models.
- To verify your setup and try the chat interface, go to LLM Chat. Try asking the LLM to generate an applet. (Note: for microphone input, you must be on localhost or HTTPS.)
- Create a course using the Course Manager, or by asking the LLM. Next, generate a course outline.
- You can then create lessons and lesson plans, again optionally using the LLM. 
- When the first lesson plan is ready, mark it as published. Be sure to add resources. (Obviously, for actual use, review everything first.) 
- Add a student account from the teacher's dashboard or using the student signup code. 
- The student can then go to their dashboard and start the lesson.

## Feature ideas:
- Periodic student profile generation
- Teacher alerts, notifications, mobile push, etc. 
- Improve curriculum design:
   - web search / open textbook / deep research support
   - Automated resource finding/validation 
- MCP support
- Student analytics (time spent, etc.)
- Resource tagging, archive
- Camera input/snapshots (e.g. show the LLM your desk)
- Hide more advanced settings/features under a Power User setting
- Python applets (pyodide iframe)
- Speed up audio input with ffmpeg to reduce cost
- Experiment with live/realtime APIs for voice lessons - if not cost-prohibitive

## Contributor guidelines:
Maintain the core app principles:
- Do not vibe-code without fully reviewing and iterating on your code. To prompt with the full codebase, repomix.config.json is included.
- The goal is to meet or exceed the level of a private tutor 
- Self-hostable, and ideally improve in this respect
- Suitable for all student ages
- Follow generally accepted Rails architecture, keep models heavy, controllers light, code easy to follow and commented.
- All LLM prompts and tools should be user-editable; use the existing models for Prompt and Tool.
- Test with different LLMs.

## License
See LICENSE.md.
