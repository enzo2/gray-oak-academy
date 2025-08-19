import { Controller } from "@hotwired/stimulus";

// Support for ManagedMediaSource (Safari) and MediaSource 
// Since we're only using audio, not video, nothing special seems to be needed for ManagedMediaSource
function getMediaSourceClass() {
  if ('ManagedMediaSource' in window) return window.ManagedMediaSource;
  if ('MediaSource' in window) return window.MediaSource;
  return null;
}

// WebM/opus is supported by MSE for streaming; Ogg/opus is not. (https://github.com/w3c/media-source/issues/245)
const mimeType = 'audio/webm;codecs=opus';

export default class extends Controller {
  static targets = ["assistantMessage", "button", "spinner"];
  static values = { speechConfigured: Boolean, autoRead: Boolean };

  // Perform checks and initialize the controller
  initialize() {
    this.audioPlayer = null;
    this.mediaSource = null;
    this.sourceBuffer = null;
    this.fetchController = null;
    this.streamReader = null;
    this.currentPlayingButton = null;
    this.chunksQueue = [];
    this.isAppending = false;
    this.isStreamEnded = false;
    this.messageId = null; // Store message ID for context if needed
    this.audioWaitingHandler = null; // For removing listener
    this.audioProgressHandler = null; // For removing listener
    this.mediaSourceClass = getMediaSourceClass();
    this.initialized = false;

    if (!this.speechConfiguredValue) {
      //console.info("TTS is not configured for the current user.");
      return;
    }

    if (!this.mediaSourceClass) {
      console.error("Media Source Extensions are not supported in this browser.");
    } else if (!this.mediaSourceClass.isTypeSupported(mimeType)) {
      console.error(`MIME type ${mimeType} not supported`);
    } else {
      // Proceed with initialization
      this.initialized = true;
    }
  }
  
  connect() {
      if (!this.initialized) return;

      // Enable existing buttons
      this.buttonTargets.forEach(button => {
        button.disabled = false;
        button.classList.remove('hidden');
      });

      // Don't auto-read the latest message initially, to avoid startling the user. 
      // Auto-reads will be triggered by the custom Turbo.StreamActions.dispatch_event 'llm-completion-finished'.
      // The listener is defined on the conversation div id="<%= dom_id(conversation) %>"
  }

  async play(event) {
    const button = event.currentTarget;
    const messageId = button.dataset.messageIdParam;
    const currentState = button.dataset.ttsStreamState || 'idle';
    const originalIconName = button.name;

    if (!this.initialized) {
      console.error("TTS Stream Controller not initialized, cannot play audio.");
      return;
    }

    if (!messageId) {
      console.error("Play clicked, but messageId is missing from button dataset:", button);
      return;
    }
    this.messageId = messageId; // Store for context during playback

    //console.log(`Play clicked: msgId=${messageId}, state=${currentState}`);

    if (currentState === 'playing' && button === this.currentPlayingButton) {
      //console.log("Stopping currently playing stream");
      this.stopPlayback();
      return;
    }

    if (currentState === 'loading' || this.mediaSource?.readyState === 'open') {
       //console.log("Already loading or playing, ignoring click");
       return;
    }

    this.stopPlayback(); // Stop any previous playback/loading

    this.setButtonState(button, 'loading', originalIconName);
    this.currentPlayingButton = button;
    this.fetchController = new AbortController();
    this.chunksQueue = [];
    this.isAppending = false;
    this.isStreamEnded = false;

    try {
      //console.log(`Fetching audio stream for message ${messageId}...`);
      const response = await fetch(`/messages/${messageId}/tts_stream`, {
        signal: this.fetchController.signal
      });

      if (!response.ok) {
        console.error(`Fetch failed for URL: /messages/${messageId}/tts_stream`);
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      if (!response.body) {
        throw new Error("Response has no body stream");
      }
      //console.log("Fetch successful, got stream body.");

      this.streamReader = response.body.getReader();
      this.mediaSource = new this.mediaSourceClass();
      this.audioPlayer = new Audio();

      // For ManagedMediaSource on iOS, disableRemotePlayback is required for the source to transition from 'closed'.
      if (typeof window.ManagedMediaSource === 'function' && this.mediaSource instanceof window.ManagedMediaSource) {
        if (this.audioPlayer.disableRemotePlayback !== undefined) {
            this.audioPlayer.disableRemotePlayback = true;
            // //console.log("ManagedMediaSource: Set audioPlayer.disableRemotePlayback = true");
        } else {
            // console.warn("ManagedMediaSource: audioPlayer.disableRemotePlayback property not available.");
        }
      }

      this.audioPlayer.src = URL.createObjectURL(this.mediaSource);
      //console.log(`MediaSource created, Audio src set: ${this.audioPlayer.src}`);

      // --- Event Listeners ---
      this.mediaSource.addEventListener('sourceopen', this.handleSourceOpen.bind(this), { once: true });
      this.mediaSource.addEventListener('sourceended', this.handleSourceEnded.bind(this));
      this.mediaSource.addEventListener('sourceclose', this.handleSourceClose.bind(this));

      // Event listeners for ManagedMediaSource (optional, logs only)
      // Should not be necessary to use, we are only streaming a small audio file
      if ('startstreaming' in this.mediaSource) {
        this.mediaSource.addEventListener('startstreaming', () => {
          //console.log('ManagedMediaSource startstreaming event');
        });
        this.mediaSource.addEventListener('endstreaming', () => {
          //console.log('ManagedMediaSource endstreaming event');
        });
        this.mediaSource.addEventListener('bufferedchange', () => {
          //console.log('ManagedMediaSource bufferedchange:', this.mediaSource.buffered);
        });
      }
      this.audioPlayer.addEventListener('error', this.handleAudioError.bind(this));
      this.audioPlayer.addEventListener('ended', this.handleAudioEnded.bind(this));
      this.audioPlayer.addEventListener('playing', this.handleAudioPlaying.bind(this));

      // Optional: Listen for waiting/progress for debugging buffering issues
      // this.audioWaitingHandler = () => //console.log(`Audio waiting for data...`);
      // this.audioPlayer.addEventListener('waiting', this.audioWaitingHandler);
      // this.audioProgressHandler = () => {
      //     if (this.audioPlayer && this.audioPlayer.buffered.length > 0) {
      //         //console.log(`Audio progress: Buffered ${this.audioPlayer.buffered.start(0)} - ${this.audioPlayer.buffered.end(0)}`);
      //     }
      // };
      // this.audioPlayer.addEventListener('progress', this.audioProgressHandler);

      // Attempt to play - browser might block until enough data or user interaction
      //console.log("Attempting initial play()");
      this.audioPlayer.play().catch(e => {
         console.warn(`Initial play() failed (may be due to browser policy): ${e.message}`);
      });

    } catch (error) {
      const logMsgId = messageId || 'N/A';
      if (error.name === 'AbortError') {
        //console.log(`Fetch aborted for message ${logMsgId}.`);
      } else {
        console.error(`Error fetching or setting up audio stream for message ${logMsgId}:`, error);
      }
      this.stopPlayback(); // Clean up on error
      this.setButtonState(button, 'idle', originalIconName); // Reset the button
      this.currentPlayingButton = null;
    }
  }

  handleSourceOpen() {
    try {
        this.sourceBuffer = this.mediaSource.addSourceBuffer(mimeType);
        //console.log("SourceBuffer added.");
        this.sourceBuffer.mode = 'sequence';

        this.sourceBuffer.addEventListener('updateend', this.handleUpdateEnd.bind(this));
        this.sourceBuffer.addEventListener('error', this.handleBufferError.bind(this));

        // Start pumping data
        //console.log("Starting stream pump.");
        this.pump();
    } catch (e) {
        console.error("Error creating SourceBuffer:", e);
        this.stopPlayback();
    }
  }

  handleSourceEnded() {
    //console.log(`MediaSource ended. State: ${this.mediaSource?.readyState}`);
  }

  handleSourceClose() {
    //console.log(`MediaSource closed. State: ${this.mediaSource?.readyState}`);
  }

  handleAudioPlaying() {
    //console.log("Audio playback started (onplaying event).");
    if (this.currentPlayingButton) {
        this.setButtonState(this.currentPlayingButton, 'playing', this.currentPlayingButton.dataset.originalIconName);
    }
  }

  handleAudioEnded() {
    //console.log("Audio playback finished (ended event).");
    this.stopPlayback(); // Clean up everything once playback is done
  }

  handleAudioError(e) {
    console.error("Audio player error:", this.audioPlayer?.error, e);
    this.stopPlayback();
  }

  handleBufferError(e) {
    console.error("SourceBuffer error:", e);
    this.stopPlayback();
  }

  handleUpdateEnd() {
    this.isAppending = false;
    //console.log(`SourceBuffer update ended. Queue size: ${this.chunksQueue.length}. Stream ended? ${this.isStreamEnded}`);
    if (this.chunksQueue.length > 0) {
      this.appendChunk(this.chunksQueue.shift());
    } else if (this.isStreamEnded) {
      this.endMediaSource();
    }
  }

  // Pump function to read from the stream and append to the buffer
  pump() {
    if (!this.streamReader) {
        //console.log("Pump called but no streamReader.");
        return;
    }

    this.streamReader.read().then(({ done, value }) => {
      if (done) {
        //console.log("Stream finished (reader.read done).");
        this.isStreamEnded = true;
        if (!this.isAppending) {
          //console.log("Stream done and not appending, calling endMediaSource.");
          this.endMediaSource();
        } else {
          //console.log("Stream done but still appending, waiting for updateend.");
        }
        return;
      }

      //console.log(`Received chunk from stream: ${value.byteLength} bytes.`);
      this.chunksQueue.push(value);
      if (!this.isAppending) {
          //console.log("Not appending, attempting to append chunk immediately.");
          this.appendChunk(this.chunksQueue.shift());
      } else {
          //console.log(`Currently appending, chunk queued. Queue size: ${this.chunksQueue.length}`);
      }
      this.pump(); // Continue pumping

    }).catch(error => {
      if (error.name === 'AbortError') {
          //console.log("Stream reader aborted.");
      } else {
          console.error("Error reading stream:", error);
      }
      this.stopPlayback();
    });
  }

  // Append a chunk to the SourceBuffer
  appendChunk(chunk) {
    if (!this.sourceBuffer || this.sourceBuffer.updating || !this.mediaSource || this.mediaSource.readyState !== 'open') {
        if (chunk) this.chunksQueue.unshift(chunk);
        // console.warn(`Buffer busy or not ready, requeuing chunk. Updating: ${this.sourceBuffer?.updating}, State: ${this.mediaSource?.readyState}`);
        return;
    }

    try {
        this.isAppending = true;
        //console.log(`Appending chunk of size ${chunk.byteLength} to SourceBuffer.`);
        this.sourceBuffer.appendBuffer(chunk);
    } catch (error) {
        console.error("Error appending buffer:", error);
        this.isAppending = false;
        this.stopPlayback();
    }
  }

  endMediaSource() {
      if (this.mediaSource && this.mediaSource.readyState === 'open') {
          if (this.sourceBuffer && !this.sourceBuffer.updating) {
              //console.log("Ending MediaSource stream.");
              try {
                  this.mediaSource.endOfStream();
              } catch (e) {
                  console.error("Error calling endOfStream:", e);
                  this.stopPlayback();
              }
          } else {
              //console.log(`Cannot end MediaSource yet, buffer updating: ${this.sourceBuffer?.updating}. Will retry on updateend.`);
          }
      } else if (this.mediaSource && this.mediaSource.readyState === 'ended') {
          //console.log("MediaSource already ended.");
      } else {
          //console.log(`Cannot end MediaSource, state: ${this.mediaSource?.readyState}, Buffer updating: ${this.sourceBuffer?.updating}`);
      }
  }

  stopPlayback() {
    //console.log("Stopping playback and cleaning up MSE...");

    if (this.fetchController) {
      this.fetchController.abort();
      this.fetchController = null;
    }

    if (this.streamReader) {
        try {
            this.streamReader.cancel().catch(e => {}); // Ignore cancellation errors
        } catch(e) {}
        this.streamReader = null;
    }

    if (this.sourceBuffer) {
        this.sourceBuffer.removeEventListener('updateend', this.handleUpdateEnd);
        this.sourceBuffer.removeEventListener('error', this.handleBufferError);
        try {
            if (this.sourceBuffer.updating) {
                this.sourceBuffer.abort();
            }
            if (this.mediaSource && this.mediaSource.readyState === 'open') {
                 try { this.mediaSource.removeSourceBuffer(this.sourceBuffer); } catch (e) {}
            }
        } catch (e) {}
        this.sourceBuffer = null;
    }

    if (this.mediaSource) {
        this.mediaSource.removeEventListener('sourceopen', this.handleSourceOpen);
        this.mediaSource.removeEventListener('sourceended', this.handleSourceEnded);
        this.mediaSource.removeEventListener('sourceclose', this.handleSourceClose);
        this.mediaSource = null;
    }

    if (this.audioPlayer) {
      this.audioPlayer.removeEventListener('error', this.handleAudioError);
      this.audioPlayer.removeEventListener('ended', this.handleAudioEnded);
      this.audioPlayer.removeEventListener('playing', this.handleAudioPlaying);
      if (this.audioWaitingHandler) this.audioPlayer.removeEventListener('waiting', this.audioWaitingHandler);
      if (this.audioProgressHandler) this.audioPlayer.removeEventListener('progress', this.audioProgressHandler);

      if (!this.audioPlayer.paused) {
        this.audioPlayer.pause();
      }
      const currentSrc = this.audioPlayer.src;
      if (currentSrc && currentSrc.startsWith('blob:')) {
        URL.revokeObjectURL(currentSrc);
      }
      this.audioPlayer.removeAttribute('src');
      this.audioPlayer.load();
      this.audioPlayer = null;
    }

    this.chunksQueue = [];
    this.isAppending = false;
    this.isStreamEnded = false;

    const buttonToReset = this.currentPlayingButton;
    this.currentPlayingButton = null;
    if (buttonToReset) {
      const originalIcon = buttonToReset.dataset.originalIconName || 'soundwave';
      if (document.body.contains(buttonToReset)) {
          this.setButtonState(buttonToReset, 'idle', originalIcon);
      }
    }
    this.messageId = null; // Clear context
  }

  setButtonState(button, state, originalIconName) {
    if (!document.body.contains(button)) return;

    const spinner = this.findSpinnerForButton(button);
    button.dataset.ttsStreamState = state;
    //console.log(`Setting button ${button.dataset.messageIdParam} state to: ${state}`);

    if (state === 'loading') {
      button.classList.add('hidden');
      if (spinner) spinner.classList.remove('hidden');
      if (!button.dataset.originalIconName) {
         button.dataset.originalIconName = originalIconName;
      }
      button.name = '';
      try { button.setAttribute('name', ''); } catch (e) {}
    } else if (state === 'playing') {
      button.classList.remove('hidden');
      if (spinner) spinner.classList.add('hidden');
      button.name = 'stop-circle';
      try { button.setAttribute('name', 'stop-circle'); } catch (e) {}
    } else { // idle or error
      button.classList.remove('hidden');
      button.disabled = false;
      if (spinner) spinner.classList.add('hidden');
      const iconName = button.dataset.originalIconName || originalIconName || 'soundwave';
      button.name = iconName;
      try { button.setAttribute('name', iconName); } catch (e) {}
      delete button.dataset.originalIconName;
    }
  }

  findSpinnerForButton(button) {
     const potentialSpinner = button.nextElementSibling;
     if (potentialSpinner && potentialSpinner.matches('[data-tts-stream-target="spinner"]')) {
       return potentialSpinner;
     }
     try {
       const controllerElement = button.closest('[data-controller~="tts-stream"]');
       if (controllerElement) {
           return Array.from(controllerElement.querySelectorAll('[data-tts-stream-target="spinner"]')).find(spinner => spinner.previousElementSibling === button);
       }
       return null;
     } catch (e) {
        return null;
     }
  }

  // Handle user toggle for auto-read
    toggleAutoRead(event) {
    this.autoReadValue = !this.autoReadValue;
    
    const iconButton = document.getElementById('auto-read-toggle');
    if (iconButton) {
      const autoName = this.autoReadValue ? 'volume-up' : 'volume-mute';
      iconButton.name = autoName;
      try { iconButton.setAttribute('name', autoName); } catch (e) {}
    }
    if (this.autoReadValue) {
      this.autoReadLatestMessage();
    }
  }

  autoReadLatestMessage() {
    if (!this.autoReadValue || !this.initialized) return;
    if (!this.hasButtonTarget) return;
    //console.log("Auto-read latest message triggered");

    // Find all TTS buttons, pick the last one (latest message)
    const lastButton = this.buttonTargets[this.buttonTargets.length - 1];
    
    // Only auto-play if not already playing
    if (lastButton && !lastButton.disabled && lastButton.dataset.ttsStreamState !== 'playing') {
      lastButton.click();
    }
  }

  // Handles the 'llm-completion-finished' event dispatched from the server
  // as soon as the completion is finished while the message continues to stream to the client
  // Enable TTS button for the message, and auto-read if enabled
  handleNewAssistantMessageFinished(event) {
    if (!this.initialized) return;

    const messageIdFromEvent = event.detail?.message_id;
    //console.log(`handleNewAssistantMessageFinished: Received event for message ID: ${messageIdFromEvent}`);

    // In case new message has not rendered yet, wait for it
    const processButton = (retryCount = 0) => {
      const targetButton = this.buttonTargets.find(btn => btn.dataset.messageIdParam === messageIdFromEvent.toString());
      if (targetButton) {
        //console.log(`Found button for message ${messageIdFromEvent} (retry ${retryCount})`);
        targetButton.disabled = false;
        targetButton.classList.remove('hidden');
        // Auto-read if enabled
        if (this.autoReadValue) this.play({ currentTarget: targetButton })
        
      } else if (retryCount < 10) { // Retry up to 1 seconds
        //console.log(`Button target for message ID ${messageIdFromEvent} not found. Retrying (${retryCount + 1})/10...`);
        setTimeout(() => processButton(retryCount + 1), 100); // Wait 100ms before retrying
      } else {
        console.error(`Could not find button target for completed message ID: ${messageIdFromEvent} after ${retryCount} retries. Was it rendered?`);
      }
    };
    // Start the process
    processButton();
  }

  disconnect() {
    //console.log("TTS Stream Controller (MSE) disconnected, stopping playback");
    this.stopPlayback();
  }
}
