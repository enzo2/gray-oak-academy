# Gray Oak Academy

## Background
Gray Oak Academy is a teacher-directed LLM tutoring platform, meant to realize the often-discussed idea that the future of education is 1-on-1 private tutoring conducted by LLMs. For totally self-directed students, a simple LLM chat may suffice. Otherwise, and especially for K-12, we need a teacher in the loop. To create a high quality LLM tutor, the minimal requirements are:
1. A curriculum management component, so that a supervising teacher can specify what is being taught, with LLM assistance.
2. A learning resource management component, to enable use of resources that are not part of an LLM's knowledge base, like books, videos, websites, software, physical items, people. By definition, this cannot be LLM-based.
3. Prompt transparency: the ability to edit the base prompts defining the teaching methodology, principles, and values for the LLM to follow. 
4. RAG and/or ultra-long-context prompting in order to take into account previous lessons and student performance. (The teacher should also review LLM-generated progress reports.)
5. An LLM chat interface, prompted with all of the above, that can function at or above the level of a private tutor. Therefore, it needs multimodal interaction, adequate screen space to interact with the student in an arbitrary way (like a desk-*Not* cell phone-friendly), and sandboxed generative UI, including code execution.

The system should ideally improve upon the supervising teacher's plan. This could include teaching more foundationally, adapting to the student's progress, and generating just-in-time applets and games. It could even break into the real world—for example, if "3D printer" were marked as a resource, the LLM could develop a device in concert with the student, generate an OpenSCAD file, and ask the student to print it for the next lesson. Such things may be beyond the current generation of LLMs, but there is already plenty of unexplored territory.

In other words, this is the opposite of the "do my homework for me" status quo that has arisen in the ChatGPT era. The idea of cheating or misusing LLMs is essentially excluded. "Homework", if any, would shift toward exploratory learning and meaningful application. Teachers will be challenged to incorporate a variety of tangible tools, demonstrations, and even human resources, to hold students' interest. The teacher will also be freed up to consider each student's overall trajectory. Students should immediately feel satisfied that their new knowledge is practical and useful.

**Gray Oak Academy is a prototype of this system.**

*I'm a doctor, Jim, not a software engineer.* Please forgive any rookie errors or lack of best practices. 

**App is at an early stage. Contributions welcome.** 

## Features
- Self-hostable with docker
- Works with any OpenAI-compatible API
- Teacher and Student views, dark mode
- Native LLM chat interface with image support
- Lesson view with LLM tool use, and "chalkboard", a multipurpose frame accessible to the LLM
- Curriculum management: Courses, Lessons, Lesson Plans
- One-click LLM generation of course outlines, lesson list, and lesson plans
- Learning resource management (linkable to lessons) 
- LLM can create and run Javascript applets
- At the end of lessons, the LLM generates a student report, which is fed into the next session, allowing the whole course to be personalized.

### More cool stuff
- Default set of base prompts in the DB seeds (obviously, these are opinionated)
- Cost/token tracking
- App name can be changed via env variable
- Fast interface with Turbo Frames/Streams
- Dark/Light mode
- NO plan for mobile support due to the need for adequate screen space.

### Frameworks, Tooling, etc.
 - Rails 8, Ruby 3.4.1
 - Turbo/Stimulus
 - Postgres 
 - Tailwind + Shoelace components
 - No node/yarn, just importmaps
 - OpenAI-compatible LLM API support (tested with OpenRouter and OpenAI)
 
### Planned Features
- STT, TTS, and native voice model support (turn-based, then realtime)
  - Allow teacher to set lessons as text-only, STT/TTS, realtime native voice, non-streamed native voice, etc.
- Webcam streaming to multimodal LLM (e.g. show the LLM what's on your desk)
- Finish resource file support (LLM access to saved files, LLM tool to display image/pdf)
- Context limit management, so user knows when they need to
- RAG: pgvector + neighbor gem (only if we are maxxing out context limits)
- Resource suggestions to the teacher based on lesson goals
- Resource archive and use tracking

### Security
- Devise for authentication
- Teacher/Admin and Student roles
- Designed for Docker use in a local secure environment
- Not designed for hosting on the public internet by default. You will need to secure the app yourself by adding a reverse proxy, modifying the Dockerfile, production.rb, etc. 
- Note! The LLM is empowered to auto-run its own Javascript in the browser, within the limits of a sandboxed iframe. To disable this function, edit code_executor_controller.js and the generative_guidelines prompt.

## Setup Instructions
- Create an account on OpenRouter and get an API key, or use another LLM API. (OpenRouter will allow you to avoid token limits, try different models easily, and track exact costs.)
- .env files must be set up with the requisite variables. See the example files. 
- If you're just trying out the app, run it with docker compose in production mode as below.
- Development mode is useful for viewing more detailed logs and debugging, but it's slow.

### Production / Personal use:
- Create `/.env.production`: see `.env.production.example`. 
- Also create `/.env`: see `.env.example`. 
- Create `/config/credentials/production.key` and add a random 32-character string.
- Build and run with docker: `docker compose up -d`. Visit http://localhost:3001.
- *The default setup is not secure and is meant for local use only. It just runs the Puma server. You can add Thruster, Rails' default proxy with Let's Encrypt support, in the Dockerfile. If serving over the internet, you'll also need to adjust settings in `/config/production.rb`. Please refer to Rails and Thruster documentation.*

### Development: 
- Create `/config/credentials/development.key` and add a random 32-character string.
- Create `/.devcontainer/.env.development`: see `/.devcontainer/.env.development.example`. 
- Open the devcontainer with VSCode, etc.
- Run a server with: `bin/dev`. Visit http://localhost:3000. You can now modify the code without having to restart the server.
- Note: the app will be slow. To actually use it, build with production settings (see above).

### Choosing an LLM:
- Model must support tool use.
- For outline/lesson generation, model must support structured outputs.
- You must use a fairly intelligent LLM like claude-3.5-sonnet, or you may encounter issues related to tool use and structured outputs. (You may be surprised that supposedly high-performing models like DeepSeek-V3 perform inconsistently.) 
- Model should have long context limit. Long lesson durations may necessitate a 1 megatoken context limit!
- Providers supporting automated prompt caching will save you money. 

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

### Hints
- When outlining a course, the grade level is useful for tuning the LLM's response. It doesn't have the be the exact grade level of the student.
- If adding a Youtube URL as a resource, make sure you use the embeddable URL. 

## Contributor guidelines:
Maintain the core app principles:
- The goal is to meet or exceed the level of a private tutor 
- Self-hostable, and ideally improve in this respect
- Suitable for all ages
- Follow generally accepted Rails architecture, keep controllers light, models heavy, code easy to follow
- All LLM prompts should be user-editable; use the Prompts model. 
- Test with various LLMs

## License
See LICENSE.md.