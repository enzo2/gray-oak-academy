# Gray Oak Academy

## Background
Gray Oak Academy is a teacher-directed LLM tutoring platform, meant to realize the often-discussed idea that the future of education is 1-on-1 private tutoring conducted by LLMs. 

For totally self-directed students, a simple LLM chat may suffice. Otherwise—and especially for K-12—we need a teacher in the loop. For a high quality LLM tutor, the minimum feature set of the "LLM wrapper" includes:
1. Curriculum management, so that a supervising teacher can specify what is being taught by the LLM, with arbitrary specificity/leeway.
2. Learning resource management, to (1) enable use of resources that are not part of an LLM's knowledge base (e.g. books, videos, websites, software), and (2) bridge the LLM into the physical world, allowing reference to items, tools, even people and human resources. 
3. Prompt transparency: a strong set of user-editable prompts defining the teaching methodology, principles, and values for the LLM to follow. 
4. RAG and/or ultra-long-context prompting in order to take into account previous lessons and student performance.
5. An LLM chat interface with interactivity comparable to a real tutor sitting across the desk, including full multimodality, generative UI, sandboxed code execution, and perhaps a webcam view of the student's desk.

The system should ideally improve upon the supervising teacher's plan. This could include teaching more foundationally, adapting to the student's progress, and generating just-in-time applets and games. It could even break into the real world—for example, if "3D printer" were marked as a resource, the LLM could develop a device in concert with the student, generate an OpenSCAD file, and ask the student to print it for the next lesson. Such things may be beyond the current generation of LLMs, but there is already plenty of unexplored territory.

This system should negate the arguments made in Isaac Asimov's 1951 story ["The Fun They Had"](http://visual-memory.co.uk/daniel/funtheyhad.html), namely that an AI homeschool tutor would be boring, unadaptable, and overly reliant on "screen time" and tedious homework rather than tactile resources and social experiences. But as with traditional home- or small-group schooling, the supervisory teacher (or parent) remains responsible for keeping the student engaged and inspired by supplying a broad set of resources and experiences, monitoring progress, and adjusting the curriculum and prompts. If not, Asimov will be vindicated.

"Do my homework for me" is the status quo that has arisen in the ChatGPT era. But with the LLM running the show, the idea of cheating or misusing LLMs is essentially excluded. "Homework", if any, would shift toward exploratory learning and meaningful application. The teacher will also be freed up to consider each student's overall trajectory. Students will immediately feel satisfied that their new knowledge is practical and useful.

**Gray Oak Academy is a prototype of this system.**

*I'm a doctor, Jim, not a software engineer.* I started this as a personal project. Please forgive any rookie errors or lack of best practices. 

**App is at an early stage. Contributions welcome.** 

## Features
- Self-hostable with docker
- Works with any OpenAI-compatible API (including locally hosted)
- Native LLM chat interface with image support
- Student lesson view with LLM tool use, and "chalkboard", a multipurpose frame accessible to the LLM
- Teacher view with full curriculum management: Courses, Lessons, Lesson Plans, and Resources
- One-click LLM generation of course outlines, lesson list, and lesson plans
- LLM can create and run Javascript applets, display files and URLs, and decide when the lesson is complete
- LLM-generated student reports are fed into the next session, allowing the whole course to be personalized.

### More cool stuff
- All prompts can be customized (default set of prompts included)
- Automated context limit tracking (when using OpenRouter)
- Cost/token tracking
- App name can be changed via env variable
- Snappy interface using Turbo & Stimulus
- Dark/Light mode

### Frameworks, Tooling, etc.
 - Rails 8, Ruby 3.4.1
 - Turbo/Stimulus
 - Postgres
 - Tailwind + Shoelace components
 - No node, just importmaps
 - OpenAI-compatible API support (tested with OpenRouter, OpenAI, and Gemini API)
 
### Planned Features
- STT/TTS/native audio model support (turn-based vs. realtime)
- Allow teacher to specify lessons as text-only, STT/TTS, native voice
- Webcam streaming to multimodal LLM (e.g. show the LLM what's on your desk)
- Add LLM reasoning support to course/lesson/plan generation
- RAG: pgvector + neighbor gem (only if we are maxxing out context limits)
- Resource suggestions to the teacher based on lesson goals
- Resource archive and use tracking
- Teacher notifications, mobile push notifications, etc.
- Tailwind v4 upgrade
- Hide more advanced features under a Power User mode
- Make it easier for less intelligent LLMs to follow the instructions for generative applets
- No plan for mobile support due to the need for adequate screen space.

### Security
- Devise for authentication
- Teacher/Admin and Student roles
- Designed for containerized use in a local secure environment
- Not designed for hosting on the public internet by default. You will need to secure the app yourself by adding a reverse proxy, modifying the Dockerfile, production.rb, etc. 
- Note: The LLM is empowered to auto-run its own Javascript in the browser, within the limits of a sandboxed iframe. To disable this function, edit code_executor_controller.js and the generative_guidelines prompt.

## Setup Instructions
- Create an account on OpenRouter and get an API key, or use another OpenAI-compatible API. (OpenRouter will allow you to avoid token limits, track exact costs, try different models easily, and track context window usage.)
- `git clone` the repository to your machine. Docker is needed. 
- Set up .env files. See the example files. 
- If you're just trying it out and don't care to see detailed logs, use a production environment with docker compose, as per below. Or, for development, use the devcontainer.

### Production:
- Create `/.env.production`: see `.env.production.example`. 
- Also create `/.env`: see `.env.example`. 
- Create `/config/credentials/production.key` and add a random 32-character string.
- Build and run with docker: `docker compose up -d`. Visit http://localhost:3001.
- *The default setup is not secure and is meant for local use only. It just runs the Puma server. You can add Thruster, Rails' default proxy with Let's Encrypt support, in the Dockerfile. If serving over the internet, you'll also need to adjust settings in `/config/production.rb`. Please refer to Rails and Thruster documentation.*

### Development: 
- Create `/config/credentials/development.key` and add a random 32-character string.
- Create `/.devcontainer/.env.development`: see `/.devcontainer/.env.development.example`. 
- Note: If using Windows with WSL2 and Docker Desktop, clone into your WSL filesystem (e.g. \\wsl.localhost\Ubuntu), otherwise it will be super slow.
- Open with VSCode, etc, and open the dev container. (If using Windows, use the WSL extension and 'Connect to WSL' first.)
- Run a server with: `bin/dev`. Visit http://localhost:3000. You can now modify the code without having to restart the server.

### Choosing an LLM & API:
- Model must support images and tool use. A long context window is recommended.
- For outline/lesson generation, model must support structured outputs.
- You must use a fairly intelligent LLM, or you may encounter issues related to tool use, generative applets, and lesson pacing. This app is quite demanding of LLMs.
- Sonnet 3.7 seems to do best overall, whereas Gemini 2.0 Flash is adequate in most cases, plus it's cheaper & has a 1 megatoken context window. GPT-4o does not perform well. 
- Providers supporting automated prompt caching are recommended to reduce costs.

## Getting Started
- Create a teacher account using the teacher signup code.
- Go to Settings > Preferences if you want to change the model from what's specified in the environment variable. 
- Go to Prompts if you want to review your system prompts.
- To verify your setup and try the chat interface, go to LLM Chat. (Note: If Firefox fails to maintiain the Websockets connection, try Edge.)
- Try asking the LLM to generate an applet, e.g. "Please make an interactive applet demonstrating refraction of light."
- Start by creating a course. To use the LLM to outline the course, save it and then press Generate Outline.
- You can then create lessons and lesson plans, again optionally using the LLM. Obviously, review everything first. 
- When the lesson plan is ready, mark it as published. You can also add resources.
- Make a student account. On the teacher account, go to Students, adopt the student, and enroll them in the course.
- The student can then go to their dashboard and try out the lesson.

## Contributor guidelines:
Maintain the core app principles:
- The goal is to meet or exceed the level of a private tutor 
- Self-hostable, and ideally improve in this respect
- Suitable for all ages
- Follow generally accepted Rails architecture, keep controllers light, models heavy, code easy to follow
- OK to code with LLMs, but do not vibe-code, and fully review your code
- All LLM prompts should be user-editable; use the Prompts model. 
- Test with different LLMs.  

## License
See LICENSE.md.