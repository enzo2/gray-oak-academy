import { Controller } from "@hotwired/stimulus";

function getMediaSourceClass() {
  if ('ManagedMediaSource' in window) return window.ManagedMediaSource;
  if ('MediaSource' in window) return window.MediaSource;
  return null;
}

// quick utility to check support, also handles feature-detect
function hasMediaSourceSupport() {
  return !!getMediaSourceClass();
}

export default class extends Controller {
  static targets = ["button", "spinner"];

  connect() {
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
    // console.log("TTS Stream Controller (MSE) connected");

    if (!this.mediaSourceClass) {
      console.error("Media Source Extensions are not supported in this browser.");
      this.targets.findAllElements('[data-tts-stream-target="button"]').forEach(btn => {
        btn.disabled = true;
        btn.title = "Streaming not supported by browser";
      });
    }
  }

  async play(event) {
    const button = event.currentTarget;
    const messageId = button.dataset.messageIdParam;
    const currentState = button.dataset.ttsStreamState || 'idle';
    const originalIconName = button.name;

    if (!messageId) {
      console.error("Play clicked, but messageId is missing from button dataset:", button);
      return;
    }
    this.messageId = messageId; // Store for context during playback

    // console.log(`Play clicked: msgId=${messageId}, state=${currentState}`);

    if (!this.mediaSourceClass) {
      console.error("MediaSource not supported.");
      return;
    }

    if (currentState === 'playing' && button === this.currentPlayingButton) {
      // console.log("Stopping currently playing stream");
      this.stopPlayback();
      return;
    }

    if (currentState === 'loading' || this.mediaSource?.readyState === 'open') {
       // console.log("Already loading or playing, ignoring click");
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
      // console.log(`Fetching audio stream for message ${messageId}...`);
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
      // console.log("Fetch successful, got stream body.");

      this.streamReader = response.body.getReader();
      this.mediaSource = new this.mediaSourceClass();
      this.audioPlayer = new Audio();
      this.audioPlayer.src = URL.createObjectURL(this.mediaSource);
      // console.log(`MediaSource created, Audio src set: ${this.audioPlayer.src}`);

      // --- Event Listeners ---
      this.mediaSource.addEventListener('sourceopen', this.handleSourceOpen.bind(this), { once: true });
      this.mediaSource.addEventListener('sourceended', this.handleSourceEnded.bind(this));
      this.mediaSource.addEventListener('sourceclose', this.handleSourceClose.bind(this));

      // Event listeners for ManagedMediaSource (optional, logs only)
      if ('startstreaming' in this.mediaSource) {
        this.mediaSource.addEventListener('startstreaming', () => {
          //console.log('ManagedMediaSource startstreaming event');
        });
        this.mediaSource.addEventListener('endstreaming', () => {
          //console.log('ManagedMediaSource endstreaming event');
        });
        this.mediaSource.addEventListener('qualitychange', () => {
          //console.log('ManagedMediaSource qualitychange:', this.mediaSource.quality);
        });
        this.mediaSource.addEventListener('bufferedchange', () => {
          //console.log('ManagedMediaSource bufferedchange:', this.mediaSource.buffered);
        });
      }
      this.audioPlayer.addEventListener('error', this.handleAudioError.bind(this));
      this.audioPlayer.addEventListener('ended', this.handleAudioEnded.bind(this));
      this.audioPlayer.addEventListener('playing', this.handleAudioPlaying.bind(this));

      // Optional: Listen for waiting/progress for debugging buffering issues
      // this.audioWaitingHandler = () => console.log(`Audio waiting for data...`);
      // this.audioPlayer.addEventListener('waiting', this.audioWaitingHandler);
      // this.audioProgressHandler = () => {
      //     if (this.audioPlayer && this.audioPlayer.buffered.length > 0) {
      //         console.log(`Audio progress: Buffered ${this.audioPlayer.buffered.start(0)} - ${this.audioPlayer.buffered.end(0)}`);
      //     }
      // };
      // this.audioPlayer.addEventListener('progress', this.audioProgressHandler);

      // Attempt to play - browser might block until enough data or user interaction
      // console.log("Attempting initial play()");
      this.audioPlayer.play().catch(e => {
         console.warn(`Initial play() failed (may be due to browser policy): ${e.message}`);
      });

    } catch (error) {
      const logMsgId = messageId || 'N/A';
      if (error.name === 'AbortError') {
        // console.log(`Fetch aborted for message ${logMsgId}.`);
      } else {
        console.error(`Error fetching or setting up audio stream for message ${logMsgId}:`, error);
      }
      this.stopPlayback(); // Clean up on error
      this.setButtonState(button, 'idle', originalIconName); // Reset the button
      this.currentPlayingButton = null;
    }
  }

  handleSourceOpen() {
    // console.log("MediaSource opened");
    const mimeType = 'audio/aac'; //firefox does not support ogg with Opus
    if (!MediaSource.isTypeSupported(mimeType)) {
        console.error(`MIME type ${mimeType} not supported`);
        this.stopPlayback();
        return;
    }
    // console.log(`Using MIME type: ${mimeType}`);

    try {
        this.sourceBuffer = this.mediaSource.addSourceBuffer(mimeType);
        // console.log("SourceBuffer added.");
        this.sourceBuffer.mode = 'sequence';

        this.sourceBuffer.addEventListener('updateend', this.handleUpdateEnd.bind(this));
        this.sourceBuffer.addEventListener('error', this.handleBufferError.bind(this));

        // Start pumping data
        // console.log("Starting stream pump.");
        this.pump();
    } catch (e) {
        console.error("Error creating SourceBuffer:", e);
        this.stopPlayback();
    }
  }

  handleSourceEnded() {
    // console.log(`MediaSource ended. State: ${this.mediaSource?.readyState}`);
  }

  handleSourceClose() {
    // console.log(`MediaSource closed. State: ${this.mediaSource?.readyState}`);
  }

  handleAudioPlaying() {
    // console.log("Audio playback started (onplaying event).");
    if (this.currentPlayingButton) {
        this.setButtonState(this.currentPlayingButton, 'playing', this.currentPlayingButton.dataset.originalIconName);
    }
  }

  handleAudioEnded() {
    // console.log("Audio playback finished (ended event).");
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
    // console.log(`SourceBuffer update ended. Queue size: ${this.chunksQueue.length}. Stream ended? ${this.isStreamEnded}`);
    if (this.chunksQueue.length > 0) {
      this.appendChunk(this.chunksQueue.shift());
    } else if (this.isStreamEnded) {
      this.endMediaSource();
    }
  }

  pump() {
    if (!this.streamReader) {
        // console.log("Pump called but no streamReader.");
        return;
    }

    this.streamReader.read().then(({ done, value }) => {
      if (done) {
        // console.log("Stream finished (reader.read done).");
        this.isStreamEnded = true;
        if (!this.isAppending) {
          // console.log("Stream done and not appending, calling endMediaSource.");
          this.endMediaSource();
        } else {
          // console.log("Stream done but still appending, waiting for updateend.");
        }
        return;
      }

      // console.log(`Received chunk from stream: ${value.byteLength} bytes.`);
      this.chunksQueue.push(value);
      if (!this.isAppending) {
          // console.log("Not appending, attempting to append chunk immediately.");
          this.appendChunk(this.chunksQueue.shift());
      } else {
          // console.log(`Currently appending, chunk queued. Queue size: ${this.chunksQueue.length}`);
      }
      this.pump(); // Continue pumping

    }).catch(error => {
      if (error.name === 'AbortError') {
          // console.log("Stream reader aborted.");
      } else {
          console.error("Error reading stream:", error);
      }
      this.stopPlayback();
    });
  }

  appendChunk(chunk) {
    if (!this.sourceBuffer || this.sourceBuffer.updating || !this.mediaSource || this.mediaSource.readyState !== 'open') {
        if (chunk) this.chunksQueue.unshift(chunk);
        // console.warn(`Buffer busy or not ready, requeuing chunk. Updating: ${this.sourceBuffer?.updating}, State: ${this.mediaSource?.readyState}`);
        return;
    }

    try {
        this.isAppending = true;
        // console.log(`Appending chunk of size ${chunk.byteLength} to SourceBuffer.`);
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
              // console.log("Ending MediaSource stream.");
              try {
                  this.mediaSource.endOfStream();
              } catch (e) {
                  console.error("Error calling endOfStream:", e);
                  this.stopPlayback();
              }
          } else {
              // console.log(`Cannot end MediaSource yet, buffer updating: ${this.sourceBuffer?.updating}. Will retry on updateend.`);
          }
      } else if (this.mediaSource && this.mediaSource.readyState === 'ended') {
          // console.log("MediaSource already ended.");
      } else {
          // console.log(`Cannot end MediaSource, state: ${this.mediaSource?.readyState}, Buffer updating: ${this.sourceBuffer?.updating}`);
      }
  }

  stopPlayback() {
    // console.log("Stopping playback and cleaning up MSE...");

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
    // console.log(`Setting button ${button.dataset.messageIdParam} state to: ${state}`);

    if (state === 'loading') {
      button.classList.add('hidden');
      if (spinner) spinner.classList.remove('hidden');
      if (!button.dataset.originalIconName) {
         button.dataset.originalIconName = originalIconName;
      }
      button.name = '';
    } else if (state === 'playing') {
      button.classList.remove('hidden');
      if (spinner) spinner.classList.add('hidden');
      button.name = 'stop-circle';
    } else { // idle or error
      button.classList.remove('hidden');
      button.disabled = false;
      if (spinner) spinner.classList.add('hidden');
      button.name = button.dataset.originalIconName || originalIconName || 'soundwave';
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

  disconnect() {
    // console.log("TTS Stream Controller (MSE) disconnected, stopping playback");
    this.stopPlayback();
  }
}