import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["recordButton", "helpText", "textarea"]
  static values = { conversationId: String, audioPermitted: Boolean }

  connect() {
    // If not secure, don't bother initializing, as MediaRecorder won't work.
    if (!window.isSecureContext) {
      console.warn("Audio recording requires a secure context (HTTPS or localhost).");
      this.recordButtonTarget.classList.add("hidden");
      return; 
    }
    
    // Check if the browser supports the MediaRecorder API
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.recordButtonTarget.classList.add("hidden")
      return
    // Check if audio is enabled for the conversation (button won't be hidden)
    } else if (this.recordButtonTarget.classList.contains("hidden"))  {
      return;
    } else {
      this.textareaTarget.placeholder = "Type your message or record audio..."
    }

    this.isRecording = false
    this.mediaRecorder = null
    this.audioChunks = []
    this.recordingTimer = null
    this.MAX_RECORDING_TIME = 30000 // 30 seconds in milliseconds
  }

  async toggleRecording() {
    if (this.isRecording) {
      this.stopRecording()
    } else {
      await this.startRecording()
    }
  }

  async startRecording() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.recordButtonTarget.classList.add("text-red-500")
      this.recordButtonTarget.name = "stop-circle" // Change icon to stop
      this.helpTextTarget.textContent = "Recording..."
      this.helpTextTarget.classList.remove("hidden")
      this.isRecording = true
      this.audioChunks = []

      const options = {
        mimeType: 'audio/webm;codecs=opus',
        audioBitsPerSecond: 32000 // Adjust bitrate as needed
        // We can't set the sample rate and bit depth, so just convert these on the server.
      }

      // Check if the preferred mimeType is supported
      if (!MediaRecorder.isTypeSupported(options.mimeType)) {
         console.warn(`${options.mimeType} is not supported. Falling back to default.`);
         // Fallback to default or another supported type if necessary
         this.mediaRecorder = new MediaRecorder(stream);
      } else {
         this.mediaRecorder = new MediaRecorder(stream, options);
      }


      this.mediaRecorder.ondataavailable = (event) => {
        this.audioChunks.push(event.data)
      }

      this.mediaRecorder.onstop = () => {
        stream.getTracks().forEach(track => track.stop()) // Stop microphone access
        this.isRecording = false
        this.recordButtonTarget.name = "mic" // Change icon back to mic
        this.recordButtonTarget.classList.remove("text-red-500")
        this.helpTextTarget.innerText = this.helpTextTarget.dataset.defaultValue
        this.helpTextTarget.classList.add("hidden")
        const audioBlob = new Blob(this.audioChunks, { type: this.mediaRecorder.mimeType })
        this.uploadAudio(audioBlob)
        clearTimeout(this.recordingTimer) // Clear the timer
      }

      this.mediaRecorder.start()

      // Set a timer to stop recording after MAX_RECORDING_TIME
      this.recordingTimer = setTimeout(() => {
        if (this.isRecording) {
          this.stopRecording()
        }
      }, this.MAX_RECORDING_TIME)

    } catch (err) {
      console.error("Error accessing microphone:", err)
      alert(`Error: ${err.message}`)
      this.isRecording = false
      this.recordButtonTarget.name = "mic"
      this.recordButtonTarget.classList.remove("text-red-500")
      this.helpTextTarget.innerText = this.helpTextTarget.dataset.defaultValue
      this.helpTextTarget.classList.remove("hidden")
    }
  }

  stopRecording() {
    if (this.mediaRecorder && this.isRecording) {
      this.mediaRecorder.stop()
      // onstop event handler will handle the rest
    }
  }

  async uploadAudio(audioBlob) {
    const formData = new FormData()
    formData.append('audio', audioBlob, `recording-${Date.now()}.webm`)
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content')

    // Choose endpoint based on audioPermitted value
    const endpoint = this.audioPermittedValue
      ? `/conversations/${this.conversationIdValue}/audio_messages`
      : `/conversations/${this.conversationIdValue}/transcribed_messages`;
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken,
          'Accept': 'text/vnd.turbo-stream.html'
          // 'Content-Type' is automatically set by fetch for FormData
        },
        body: formData
      })
      if (!response.ok) {
        throw new Error(`Server responded with ${response.status}`)
      }
    } catch (error) {
      console.error('Error uploading audio:', error)
    }
  }

  disconnect() {
    // Ensure recording stops and resources are released if the controller disconnects
    if (this.isRecording) {
      this.stopRecording()
    }
    clearTimeout(this.recordingTimer)
  }
}