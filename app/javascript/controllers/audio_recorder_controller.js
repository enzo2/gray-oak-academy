import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["recordButton", "helpText", "textarea"]
  static values = { 
    conversationId: String, 
    audioInputPermitted: Boolean, 
    sttAvailable: Boolean, 
    audioSetting: String 
  }

  connect() {
    // By default, the recordButton is hidden. Check a series of requirements before initializing.
    if (!window.isSecureContext) {
      // If not secure, don't bother initializing, as MediaRecorder won't work.
      console.warn("Audio recording requires a secure context (HTTPS or localhost).");
      if (this.audioSettingValue == "only") { alert("Please connect using https for audio-only lessons.") }
    } else if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      // Check if the browser supports the MediaRecorder API
      console.warn("MediaRecorder API is not supported in this browser.");
      if (this.audioSettingValue == "only") { alert("The lesson is set to audio-only, but your browser does not support audio input.") }
    } else if (!this.audioInputPermittedValue && !this.sttAvailableValue) {
      // If audio input is not permitted and STT is not available, don't initialize.
      console.info("Speech input is not available for this conversation.");
      if (this.audioSettingValue == "only") { alert("The lesson is set to audio-only, but speech input was not set up. Please notify your teacher.")}
    } else { 
      //Proceed with initialization
      this.textareaTarget.placeholder = (this.audioSettingValue == "only") ? "Record your message..." : "Type or record your message...";
      this.recordButtonTarget.classList.remove("hidden");
      this.isRecording = false
      this.mediaRecorder = null
      this.audioChunks = []
      this.recordingTimer = null
      this.MAX_RECORDING_TIME = 40000 // 40 seconds in milliseconds
    }
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
      this.helpTextTarget.textContent = "Recording...press stop to send message."
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

    // Also send images_data if present
    const imagesDataField = this.element.querySelector('[data-new-message-target="imagesData"]');
    if (imagesDataField && imagesDataField.value) {
      formData.append('images_data', imagesDataField.value);
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content')

    // Choose endpoint based on audioPermitted value
    const endpoint = this.audioInputPermittedValue
      ? `/conversations/${this.conversationIdValue}/audio_messages`
      : `/conversations/${this.conversationIdValue}/transcribed_messages`;
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken,
          'Accept': 'text/vnd.turbo-stream.html'
        },
        body: formData
      })
      if (!response.ok) {
        throw new Error(`Server responded with ${response.status}`)
      }
      const html = await response.text()
      Turbo.renderStreamMessage(html)
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