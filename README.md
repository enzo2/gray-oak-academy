# Gray Oak Academy

## Background and Purpose
Gray Oak Academy is a teacher-directed, LLM-conducted learning platform, meant to realize the rather old idea that the future of education is 1-on-1 private tutoring conducted by AI. This app allows anyone to easily build lesson plans or entire courses for an LLM to teach, incorporating learning resources and generative applets, and executeing those lesson plans using any LLM.

"Do my homework for me" is the status quo of the GPT era, now widely considered a crisis in education. The answer has been to promote LLMs as study assistants—an incremental improvement. However, by deliberately and carefully teaching *through* the LLM, the potentional for academic dishonesty or wasted effort is excluded. Just as a private tutor would readily discern when a student is struggling or disinterested, an LLM conducting a lesson will always try to hold the student's interest until he or she has grasped the point. The need for homework and exams will diminish, as practice and evaluation are folded into lessons, allowing more time for exploratory learning and meaningful application. After lessons, students will feel satisfied that their new knowledge is practical and useful. The supervising (human) teacher will be freed up to spend time seeking out learning resources, incorporating more memorable experiences, refining the curriculum, and mentoring individual students. 

Since this is a major shift in educational approach (although it's old-fashioned from another perspective!), take a moment to consider what such a system ought to look like. For a high quality LLM tutor, the minimum feature set of the "LLM wrapper" includes:
1. Curriculum management, so that a supervising teacher can specify what is being taught by the LLM, with arbitrary specificity.
2. Learning resource management, to (1) enable use of resources that are not part of an LLM's knowledge base (e.g. books, videos, websites, software), and (2) bridge the LLM into the physical world, allowing reference to items, tools, even human resources. 
3. Prompt transparency: a strong set of teacher-editable prompts defining the methodology, principles, and values for the LLM to follow. 
4. Student context: prompts include information on previous lessons and student performance, enabling fluid progression and personalization.
5. Multimodal input and output, comparable to a human tutor sitting across the desk (perhaps with a webcam view of the desk), as well as adaptability via generative UI and sandboxed code execution. 
6. Because some lessons are better taught away from a computer, through casual conversation, or even outdoors, it should support speech-only mode for mobile phone use (i.e. "walk and talk"), as well as entirely offline, debrief-only lessons.

**Gray Oak Academy is a prototype of this system.**

Importantly, the system should negate the arguments made in Isaac Asimov's 1951 short story ["The Fun They Had"](http://visual-memory.co.uk/daniel/funtheyhad.html), namely that an AI homeschool tutor would be boring, unadaptable, and overly reliant on screen time and tedious homework rather than tactile resources and social experiences. This could still be a problem in the absence of human teacher. Therefore, as with traditional home- or small-group schooling, the supervisory teacher (or parent) remains responsible for keeping the student engaged and inspired by supplying a broad set of resources and experiences, monitoring progress, and adjusting the curriculum and prompts. If not, Asimov will be vindicated. However, prompted well, the LLM is positioned to improve upon the supervising teacher's curriculum and capabilities, both in the planning and execution phases.

*Notice: I'm a doctor, Jim, not a software engineer.* I started this as a personal project for homeschooling.

## Features
- Self-hostable with docker
- Works with any OpenAI-compatible API (including locally hosted)
- LLM chat supports images, native audio input, STT/TTS with auto-read
- Student lesson view with "chalkboard" (multipurpose frame accessible by the LLM)
- Curriculum management: Courses, Lessons, Lesson Plans, and Resources
- Edit curriculum with LLM assistance, or manually
- One-click generation of course outlines, lesson list, lesson plans, and suggested resources
- LLM can create and run Javascript applets, display files and URLs, and decide when the lesson is complete
- LLM-generated student reports are fed into the next session, ensuring continuity and personalization
- Speech-only and offline/debrief lesson options to reduce screen time

### More cool stuff
- All system prompts can be customized (opinionated defaults included)
- OpenRouter optimized (automated context limit tracking, actual cost tracking, LLM feature detection, image gen model support)
- API and token management: Preload multiple LLM APIs for teachers to choose from
- If LLM supports raw audio input, it will be sent and then transcribed for later completions
- Python code execution tool via [https://github.com/khoj-ai/terrarium](URL)
- App name can be customized via env variable
- Dark/Light mode

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

### Choosing an LLM: 
- For chat/lessons, model must support images and function calling. Audio input is optional. A long context window is recommended. For speed and cost, use a non-thinking or adaptive-thinking model. You must use a fairly intelligent model, or you may encounter issues related to tool use, generative applets, and lesson pacing. This app is quite demanding of LLMs. 
- In settings, you can add a reasoning model specifically for curriculum generation tasks. Model must support structured outputs. It should be a top-performing, large-sized model. (Even some flagship models may not be good enough!)
- For image generation, while models are advancing, they are still totally unsuitable for educational uses like accurately labelled diagrams, infographics, etc. For now, the app implements a 2-pass generation to allow image in/out models to self-correct to some extent. 

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
- Improve curriculum design:
   - web search / open textbook / deep research support
   - Automated resource finding/validation 
   - Prepared applets
- MCP support
- Resource tagging, archive
- Camera input/snapshots (e.g. show the LLM your desk)
- Teacher alerts, notifications, mobile push, etc. 
- Student analytics (time spent, etc.)
- Student profile (e.g. memory tool, joint teacher-LLM understanding of the student)
- Student feedback tool at end of lessons
- Hide more advanced settings/features under a Power User setting
- Python applets (pyodide iframe)
- Speed up audio input with ffmpeg to reduce cost
- Consider RAG (pgvector + neighbor gem), but might not be needed since inexpensive long-context LLMs are now available
- Experiment with live/realtime APIs for voice lessons

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