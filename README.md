# Gray Oak Academy

## Background and Purpose
Gray Oak Academy is a teacher-directed LLM tutoring platform, meant to realize the often-discussed idea that the future of education is 1-on-1 private tutoring conducted by LLMs. This app allows anyone to quickly construct lessons or entire courses for an LLM to teach, incorporating external learning resources and generative applets, and executes those lesson plans using an LLM of choice. 

"Do my homework for me" is the status quo that has arisen in the GPT era. But with the LLM running the show, the idea of cheating or misusing LLMs is essentially excluded. Homework, if any, will shift toward exploratory learning and meaningful application. The teacher will also be freed up to consider each student's overall trajectory and incorporate more memorable experiences. Students will immediately feel satisfied that their new knowledge is practical and useful. This is possible today. Since this is a major shift in educational approach, take a moment to consider what such a system ought to look like. 

For totally self-directed students, a simple LLM chat may suffice. Otherwise—and especially for K-12—we need a teacher in the loop. For a high quality LLM tutor, the minimum feature set of the "LLM wrapper" includes:
1. Curriculum management, so that a supervising teacher can specify what is being taught by the LLM, with arbitrary specificity/leeway.
2. Learning resource management, to (1) enable use of resources that are not part of an LLM's knowledge base (e.g. books, videos, websites, software), and (2) bridge the LLM into the physical world, allowing reference to items, tools, even people and human resources. 
3. Prompt transparency: a strong set of user-editable prompts defining the teaching methodology, principles, and values for the LLM to follow. 
4. Prompts include information on previous lessons and student performance, enabling fluid progression and personalization.
5. An LLM chat interface with fully multimodal interactivity comparable to a human tutor sitting across the desk (perhaps with a webcam view of the desk), as well as adaptability via generative UI, diagramming, and sandboxed code execution. 
6. Because some lessons are better taught away from a computer, through casual conversation, should support speech-only, no-screen mode (e.g. walking outdoors).

**Gray Oak Academy is a prototype of this system.**

Importantly, the system should negate the arguments made in Isaac Asimov's 1951 story ["The Fun They Had"](http://visual-memory.co.uk/daniel/funtheyhad.html), namely that an AI homeschool tutor would be boring, unadaptable, and overly reliant on "screen time" and tedious homework rather than tactile resources and social experiences. This can still happen. But as with traditional home- or small-group schooling, the supervisory teacher (or parent) remains responsible for keeping the student engaged and inspired by supplying a broad set of resources and experiences, monitoring progress, and adjusting the curriculum and prompts. If not, Asimov will be vindicated.

Prompted well, the LLM should ideally improve upon the supervising teacher's curriculum and capabilities. This could include teaching more foundationally, adapting to the student's progress, and gamification using just-in-time applets. It will be companionable, allowing students to 'walk and talk' if they don't want to sit down. A benchmark for LLM intelligence will be their ability to creatively teach by breaking into the real world; for example, if '3D printer' were marked as a resource, the LLM could conceive of a physical demonstration, write an OpenSCAD file and have the teacher print it out in advance of the lesson. But even with the current generation of LLMs, there is plenty of unexplored territory. 

*I'm a doctor, Jim, not a software engineer.* I started this as a personal project. Please overlook any rookie errors in the code. 

## Features
- Self-hostable with docker
- Works with any OpenAI-compatible API (including locally hosted)
- Native LLM chat interface with image and audio input, TTS
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
- App name can be customized via env variable
- Dark/Light mode

### Frameworks/Tooling
 - Rails 8.0, Ruby 3.4, Postgres
 - Turbo/Stimulus
 - Tailwind CSS + Shoelace components
 - No npm, just importmaps
 - OpenAI-compatible API support (tested with OpenRouter, OpenAI, and Gemini)

### Security
- Devise for authentication
- Teacher (Admin) and Student roles
- Designed for containerized use in a local secure environment
- For security, not designed for hosting publically by default. You will need to secure the app yourself by adding a reverse proxy, modifying the Dockerfile, production.rb, etc. 
- Note: The LLM is permitted to auto-execute its own javascript within a sandboxed iframe. 

## Setup Instructions
- `git clone` the repository to your machine. Docker is needed. 
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
- Note: If using Windows with WSL2 and Docker Desktop, clone into your WSL filesystem (e.g. \\wsl.localhost\Ubuntu), otherwise it will be super slow.
- Open with VSCode, etc, and open the dev container. (If using Windows, use the WSL extension and 'Connect to WSL' first.)
- Run `rails server`. Visit http://localhost:3000. 

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

### Future feature ideas:
- Conversational/speech-only lesson plan support (STT or audio in, TTS out)
- If not cost-prohibitive, experiment with realtime, fully multimodal APIs - ?container for Pipecat with Gemini Live API
- Camera/webcam input (e.g. show the LLM your work)
- OpenAI Images API support for generative diagrams, infographics, student inspiration, etc. 
- Resource suggestions to the teacher based on lesson goals
- Resource tagging, archive, usage tracking
- Student profile (e.g. memory tool, joint teacher-LLM understanding of the student, etc.)
- Settings for reasoning models
- Incorporate student feedback form at end of lessons
- Teacher alerts, notifications, mobile push, etc. 
- Student analytics 
- Hide more advanced settings/features under a Power User mode
- Consider RAG (pgvector + neighbor gem), but might not be needed, thanks to long context window models

## License
See LICENSE.md.