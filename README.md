# Gray Oak Academy

## Background and Purpose
Gray Oak Academy is a teacher-directed LLM tutoring platform, meant to realize the often-discussed idea that the future of education is 1-on-1 private tutoring conducted by LLMs. This app allows anyone to quickly construct lessons or entire courses for an LLM to teach, incorporating learning resources and generative applets, and executes those lesson plans using an LLM of choice.

"Do my homework for me" is the status quo that has arisen in the GPT era, now widely considered a crisis in education. But with the LLM given a primary teaching role, the idea of cheating with LLMs is turned on its head. Just as a private tutor would quickly become aware when their student shows disinterest or poor understanding, an LLM conducting a lesson will always try to hold the student's interest until he or she has grasped the point. The rationale for homework—if any—would shift from evaluation toward exploratory learning and meaningful application. The supervising (human) teacher will be freed up to spend time on important tasks like incorporating more memorable experiences, seeking out learning resources, and mentoring individual students. After lessons, students will immediately feel satisfied that their new knowledge is practical and useful. 

Since this is a major shift in educational approach, take a moment to consider what such a system ought to look like. For a high quality LLM tutor, the minimum feature set of the "LLM wrapper" includes:
1. Curriculum management, so that a supervising teacher can specify what is being taught by the LLM, with arbitrary specificity/leeway.
2. Learning resource management, to (1) enable use of resources that are not part of an LLM's knowledge base (e.g. books, videos, websites, software), and (2) bridge the LLM into the physical world, allowing reference to items, tools, even people and human resources. 
3. Prompt transparency: a strong set of user-editable prompts defining the teaching methodology, principles, and values for the LLM to follow. 
4. Prompts include information on previous lessons and student performance, enabling fluid progression and personalization.
5. An LLM chat interface with fully multimodal interactivity comparable to a human tutor sitting across the desk (perhaps with a webcam view of the desk), as well as adaptability via generative UI, diagramming, and sandboxed code execution. 
6. Because some lessons are better taught away from a computer, through casual conversation, or even outdoors, it should support speech-only mode for mobile phone use.

**Gray Oak Academy is a prototype of this system.**

Importantly, the system should negate the arguments made in Isaac Asimov's 1951 story ["The Fun They Had"](http://visual-memory.co.uk/daniel/funtheyhad.html), namely that an AI homeschool tutor would be boring, unadaptable, and overly reliant on "screen time" and tedious homework rather than tactile resources and social experiences. This can still happen. But as with traditional home- or small-group schooling, the supervisory teacher (or parent) remains responsible for keeping the student engaged and inspired by supplying a broad set of resources and experiences, monitoring progress, and adjusting the curriculum and prompts. If not, Asimov will be vindicated.

Prompted well, the LLM should ideally improve upon the supervising teacher's curriculum and capabilities. This could include teaching more foundationally, adapting to the student's progress, and gamification using just-in-time applets. It should be companionable, allowing students to 'walk and talk' if they don't want to sit down. A benchmark for LLM intelligence will be their ability to creatively teach by breaking into the real world; for example, if '3D printer' were marked as a resource, the LLM could conceive of a physical demonstration, write an OpenSCAD file and have the teacher print it out in advance of the lesson. But even with the current generation of LLMs, there is plenty of unexplored territory. 

*Notice: I'm a doctor, Jim, not a software engineer.* I started this as a personal project. I hope you'll find the code logical and understandable.

## Features
- Self-hostable with docker
- Works with any OpenAI-compatible API (including locally hosted)
- Native LLM chat interface supporting images, raw audio input and STT, TTS with auto-read
- Student lesson view with LLM tool use, and "chalkboard", a multipurpose frame accessible to the LLM
- Teacher view with full curriculum management: Courses, Lessons, Lesson Plans, and Resources
- One-click LLM generation of course outlines, lesson list, and lesson plans
- LLM can create and run Javascript applets, display files and URLs, and decide when the lesson is complete
- LLM-generated student reports are fed into the next session, allowing the whole course to be personalized.

### More cool stuff
- All system prompts can be customized (opinionated defaults included)
- Automated context limit tracking (when using OpenRouter)
- Cost/token usage tracking
- Remembers API URIs and model names for easy switching
- If LLM supports raw audio input, it will be used the first time, and then transcribed for later completions (in anticipation of improvements in audio understanding models)
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
- Teacher (Admin) and Student roles
- Designed for containerized use in a local secure environment
- For security, not designed for hosting publically by default. You will need to secure the app yourself by adding a reverse proxy, modifying the Dockerfile, production.rb, etc. 
- Note: The LLM is permitted to auto-execute its own javascript within a sandboxed iframe. 

## Setup Instructions
- `git clone` the repository to your machine. Docker is needed. 
- Note: If using Windows with WSL2 and Docker Desktop, clone into your WSL filesystem (e.g. \\wsl.localhost\Ubuntu), otherwise it will be super slow.
- Set up .env files according to the examples.
- Choose an OpenAI-compatible LLM API. See below sections 'Choosing an API & LLM'.
- If you're just trying it out or don't care to see detailed logs, follow 'Production' instructions below. Or, you can use the devcontainer.

### Production:
- Create `/.env.production`: see `.env.production.example`. 
- Also create `/.env`: see `.env.example`. 
- Create `/config/credentials/production.key` and add a random 32-character string.
- Build and run with docker: `docker compose up -d`. Visit http://localhost:3001.
- *The default setup is not secure and is meant for local use only. It just runs the Puma server. You can add Thruster, Rails' default proxy with Let's Encrypt support, in the Dockerfile. If serving over the internet, you'll also need to adjust settings in `/config/production.rb`. Please refer to Rails and Thruster documentation.*

### Development: 
- Create `/config/credentials/development.key` and add a random 32-character string.
- Create `/.devcontainer/.env.development`: see `/.devcontainer/.env.development.example`. 
- Open with VSCode, etc, and open the dev container. (If using Windows, use the WSL extension and 'Connect to WSL' first.)
- Optionally, add the automatically generated `/config/certs/root-ca.crt` to your browser's trusted certificates.
- Run `rails server`. Visit https://localhost:3000. 

### Choosing an API:
- Notably, Gemini API has an OpenAI-compatible endpoint, a free tier, audio input, and 1+ megatoken context windows. 
- Built-in support for OpenRouter enables tracking actual costs and displays context window usage. OpenRouter also avoids token limits, and enables trying different providers/models easily. But no audio input. 
- For heavy users, providers supporting automated prompt caching will reduce cost.

### Choosing an LLM: 
- For chat/lessons, model must support images and function calling. Audio input is optional. A long context window is recommended. 
- For outline/lesson generation, model must support structured outputs.
- You must use a fairly intelligent LLM, or you may encounter issues related to tool use, generative applets, and lesson pacing. This app is quite demanding of LLMs. However, thinking models may have excessive latency for real-time tutoring.
- Sonnet 3.7 seems to do best overall, whereas Gemini 2 Flash is adequate and has a 1 megatoken context window, plus audio input. GPT-4o does not seem to perform well.

## Getting Started
- Create a teacher account using the teacher signup code.
- Go to Settings > Preferences if you want to change the model from what's specified in the environment variable. 
- Go to Prompts if you want to review your system prompts.
- To verify your setup and try the chat interface, go to LLM Chat. Try asking the LLM to generate an applet. (Note: for microphone input, you must be on localhost or HTTPS.)
- Start by creating a course. To use the LLM to outline the course, save it and then press Generate Outline.
- You can then create lessons and lesson plans, again optionally using the LLM. Obviously, review everything first. 
- When the lesson plan is ready, mark it as published. Be sure to add resources.
- Make a student account. On the teacher account, go to Students, adopt the student, and enroll them in the course.
- The student can then go to their dashboard and try out the lesson.

## Contributor guidelines:
Maintain the core app principles:
- Do not vibe-code without fully reviewing and iterating on your code. To prompt with the full codebase, repomix.config.json is included.
- The goal is to meet or exceed the level of a private tutor 
- Self-hostable, and ideally improve in this respect
- Suitable for all student ages
- Follow generally accepted Rails architecture, keep models heavy, controllers light, code easy to follow and commented.
- All LLM prompts and tools should be user-editable; use the existing models.
- Test with different LLMs.

### Future feature ideas:
- If not cost-prohibitive, experiment with realtime, fully multimodal APIs - ?container for Pipecat with Gemini Live API
- Camera/webcam input (e.g. show the LLM your work)
- Resource suggestions to the teacher based on lesson goals (LLM-only, or via web search APIs)
- Resource tagging, archive, usage tracking
- Agentic curriculum design (i.e. chat and iterate)
- Images output support (OpenAI Images API, Gemini API) for generative diagrams, infographics, student inspiration, etc. (once models have improved sufficiently)
- Student profile (e.g. memory tool, joint teacher-LLM understanding of the student, etc.)
- Separate LLM settings for lesson planning vs. conducting
- Settings for reasoning models
- Student feedback form at end of lessons
- Teacher alerts, notifications, mobile push, etc. 
- Student analytics 
- Hide more advanced settings/features under a Power User mode
- Consider RAG (pgvector + neighbor gem), but might not be needed if cheap long context models continue to be available.

## License
See LICENSE.md.