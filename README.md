# Gray Oak Academy

## Background
Gray Oak Academy is a teacher-directed LLM tutoring platform, meant to realize the often-discussed idea that the future of education is 1-on-1 private tutoring conducted by LLMs. For totally self-directed students, a simple LLM chat may suffice. Otherwise, and especially for K-12, we need a teacher in the loop. To create a high quality LLM tutor, the minimal requirements are:
1. A curriculum management component, so that a supervising teacher can specify what is being taught, with LLM assistance.
2. A learning resource management component, to enable use of resources that are not part of an LLM's knowledge base, like books, videos, websites, software, physical items, people. By definition, this cannot be LLM-based.
3. Prompt transparency: the ability to edit the base prompts defining the teaching methodology, principles, and values for the LLM to follow. 
4. RAG and/or ultra-long-context prompting in order to take into account previous lessons and student performance. (The teacher should also review LLM-generated progress reports.)
5. An LLM chat interface, prompted with all of the above, that can function at or above the level of a private tutor. Therefore, it needs multimodal interaction, adequate screen space to interact with the student in an arbitrary way (like a desk-*Not* cell phone-friendly), and sandboxed generative UI, including code execution.

The system should ideally improve upon the supervising teacher's plan. This could include teaching more foundationally, adapting to the student's progress, and generating just-in-time applets and games. It could even break into the real world—for example, if "3D printer" were marked as a resource, the LLM could develop a device in concert with the student, generate an OpenSCAD file, and ask the student to print it for the next lesson. Such things may not always work with the current generation of LLMs, but as cost per intelligence comes down, it's a good time to get started.

In other words, this is the opposite of the "do my homework for me" status quo that has arisen in the ChatGPT era. The idea of cheating or misusing LLMs is essentially excluded. "Homework", if any, would shift toward exploratory learning and meaningful application. Teachers will be challenged to incorporate a variety of tangible tools, demonstrations, and even human resources, to hold students' interest. The teacher will also be freed up to consider each student's overall trajectory, and adjust the curriculum accordingly. Students should immediately feel satisfied that their new knowledge is practical and useful.

**I'm a doctor, Jim, not a software engineer.** Please forgive any rookie errors. LLMs were used, of course, but not without heavy iteration. There are no tests yet, sorry.

## Features
**App is at an early stage. Contributions welcome.**
- Self-hostable with docker
- Teacher and Student views
- Curriculum management: Courses, Lessons, Lesson Plans
- One-click LLM generation of course outlines, lesson list, and lesson plans
- Resource management, linkable to lessons
- Default set of base prompts in the DB seeds (obviously, these are opinionated)
- Native LLM chat with image support
- Lesson view with LLM tool use, and "chalkboard", a multipurpose frame accessible to the LLM
- LLM can create and run Javascript applets, access browser APIs
- LLM can complete the lesson and save the lesson summary
- App name can be changed via env variable
- NO plan for mobile support, as this would not allow the needed large screen area. 

### Frameworks, Tooling, etc.
 - Rails 8, Postgres, Hotwire 
 - Ruby 3.4.1
 - Tailwind + Shoelace components
 - LLM API: OpenRouter (this avoids token limits and allows trying different models easily)

### Planned Major Features
- Chalkboard screen capturing
- Webcam streaming to multimodal LLM (e.g. show the LLM what's on your desk)
- STT and TTS
- Native voice model support (turn-based, then realtime)
- Allow teacher to set lessons as text-only, STT/TTS, realtime native voice, non-streamed native voice, etc.
- RAG: pgvector + neighbor gem
- Additional chalkboard tools (drawing pad, send screenshot to LLM)
- Finish resource file support (LLM access to saved files)
- Additional LLM tools: activate drawing pad, retrieve screenshot, display resource (image/pdf)
- Cost tracking
- Resource suggestions to the teacher based on lesson goals
- Resource archive and use tracking
- Support any openAI-compatible API / local inference servers

### Security
- Devise for authentication
- Teacher/Admin and Student roles
- Designed for Docker use in a local secure environment
- Not designed for exposure to public internet. SSL not forced by default. If you want to make it publically available, make sure you configure config.assume_ssl and config.force_ssl in config/environments/production.rb.
- Note! The LLM is empowered to auto-run its own Javascript in the browser, within the limits of a sandboxed iframe. To disable this function, edit code_executor_controller.js and the generative_guidelines prompt.


## Setup Instructions
Create an account on OpenRouter and get an API key.

For a development server using devcontainer, create `.env.development` in the .devcontainer folder, and add the required variables as below.
Create /config/credentials/development.key and add a random 32-character string.
Open the devcontainer with VSCode, etc.
Run a server with bin/dev. 

For a production server, create `.env` and `.env.production` in the root folder. Add the required variables as below.
Create /config/credentials/production.key and add a random 32-character string.
The default setup is not secure. It runs a server using Thruster and exposes port 80. Ensure this port is not in use by another process on your host machine, and is firewalled from the public internet, unless you set up SSL.
Confirm your settings in production.rb. Pay attention to config.assume_ssl and config.force_ssl if you plan on exposing the server or using a reverse proxy. 
To only use Puma without Thruster, change the commented lines in the Dockerfile. 
To build and run with docker, run `docker compose up -d`.

### .env Files

-   `/.env`:
    ```
    #Postgres container doesn't need the full .env.production, so just put the DB_PASSWORD here for use by docker-compose.yml.
    DB_PASSWORD=....
    ```
-   `/.devcontainer/.env.development` and `/.env.production`: see `.env.production.example`. 

## How to Use
 
- Create a teacher account using the teacher signup code.
- Go to Settings > Preferences if you want to change the model from what's specified in the environment variable. Some models are better at tool use and instruction-following than others. Try different ones. (Ensure your database is secure before adding any API keys.)
- Go to Prompts if you want to change your system prompts.
- Start by creating a course. To use the LLM to outline the course, save it and then press Generate Outline.
- You can then create lessons and lesson plans, again optionally using the LLM. Obviously, review everything first. 
- When the lesson plan is ready, mark it as published. You can also add resources.
- Make a student account. On the teacher account, go to Students, adopt the student, and enroll them in the course.
- The student can then go to their dashboard and try out the lesson.
- To just try out the LLM outside of a lesson, go to LLM Chat.
- Ask the LLM to generate an applet, e.g. "Please make an interactive applet demonstrating refraction of light."


## Contributor guidelines:
Maintain the core app principles:
- The goal is to meet or exceed the level of a private tutor 
- Self-hostable, and ideally improve in this respect
- Suitable for all ages
- Follow generally accepted Rails architecture, keep controllers light, models heavy
- Make the code easy to follow / approachable so that a wide audience may contribute. 
- All LLM prompts should be user-editable, and avoid testing with only one particular LLM

## License
This project is licensed under the AGPL v3. See LICENSE.md.