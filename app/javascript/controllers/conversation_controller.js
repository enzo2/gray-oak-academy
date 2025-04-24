import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "user", "assistant", "assistantContent", "ttsButton"]

  connect() {
    this.scrollToBottom()
    this.audioPlayer = null; // To hold the current Audio object
    this.currentPlayingButton = null; // To track which button is playing
  }

  scrollToBottom() {
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth' })
    }
  }

  renderKatexInMessages() {
    this.assistantTargets.forEach(message => {
      renderMathInElement(message, {
        delimiters: [
            {left: "$$", right: "$$", display: true},
            {left: "$", right: "$", display: false},
            {left: "\\[", right: "\\]", display: true}
        ],
        throwOnError: false
      });
    });
  }

  userTargetConnected(element) {
    this.scrollToBottom()
  }

  assistantTargetConnected(element) {
    this.renderKatexInMessages()
    this.scrollToBottom()
  }

  assistantContentTargetConnected(element) {
    this.renderKatexInMessages()
  }

  async playTTS(event) {
    const button = event.currentTarget;
    const messageId = button.dataset.messageIdParam;
    const currentState = button.dataset.ttsState || 'idle';

    if (!messageId) {
      console.error("Could not find message ID for TTS");
      return;
    }

    // If the clicked button is the one currently playing, stop playback
    if (currentState === 'playing' && button === this.currentPlayingButton) {
      this.stopPlayback();
      return;
    }

    // Prevent starting a new request if already loading or playing another audio
    if (currentState === 'loading' || (this.audioPlayer && !this.audioPlayer.paused)) {
      console.warn("TTS request ignored: Already loading or playing.");
      return;
    }

    // Stop any previous playback before starting a new one
    this.stopPlayback();

    const originalIconName = button.name; // Store original icon

    try {
      this.setButtonState(button, 'loading', originalIconName);
      this.currentPlayingButton = button; // Tentatively set the button

      const response = await fetch(`/messages/${messageId}/tts`);
      if (!response.ok) {
        const errorText = response.statusText || `HTTP error! status: ${response.status}`;
        throw new Error(errorText);
      }

      const audioBlob = await response.blob();
      const audioUrl = URL.createObjectURL(audioBlob);
      this.audioPlayer = new Audio(audioUrl);

      this.audioPlayer.oncanplaythrough = () => {
        this.setButtonState(button, 'playing', originalIconName);
        this.audioPlayer.play();
      };

      this.audioPlayer.onended = () => {
        this.resetButtonState(button, originalIconName);
        URL.revokeObjectURL(audioUrl);
        this.audioPlayer = null;
        this.currentPlayingButton = null;
      };

      this.audioPlayer.onerror = (e) => {
        console.error("Error playing audio:", e);
        this.resetButtonState(button, originalIconName);
        URL.revokeObjectURL(audioUrl);
        this.audioPlayer = null;
        this.currentPlayingButton = null;
      };

      // Handle cases where oncanplaythrough might not fire reliably (e.g., cached audio)
      // Or if the audio loads very quickly.
      if (this.audioPlayer.readyState >= 3) { // HAVE_FUTURE_DATA or HAVE_ENOUGH_DATA
          this.setButtonState(button, 'playing', originalIconName);
          this.audioPlayer.play();
      }

    } catch (error) {
      console.error("Error fetching or playing TTS:", error);
      this.resetButtonState(button, originalIconName);
      this.audioPlayer = null;
      this.currentPlayingButton = null;
    }
  }

  stopPlayback() {
    if (this.audioPlayer && !this.audioPlayer.paused) {
      this.audioPlayer.pause();
      this.audioPlayer.currentTime = 0; // Reset playback position
      // The onended event won't fire naturally, so manually reset the button
      if (this.currentPlayingButton) {
        const originalIcon = this.currentPlayingButton.dataset.originalIconName || 'volume-up';
        this.resetButtonState(this.currentPlayingButton, originalIcon);
      }
      // Clean up URL object if it exists from the audio source
      if (this.audioPlayer.src.startsWith('blob:')) {
        URL.revokeObjectURL(this.audioPlayer.src);
      }
    }
    this.audioPlayer = null;
    this.currentPlayingButton = null;
  }

  setButtonState(button, state, originalIconName) {
    button.dataset.ttsState = state;
    button.disabled = true; // Disable button in loading/playing states

    // Store original icon if not already stored
    if (!button.dataset.originalIconName) {
        button.dataset.originalIconName = originalIconName;
    }

    // Clear existing content (icon/spinner)
    while (button.firstChild) {
        button.removeChild(button.firstChild);
    }
    button.name = ''; // Clear Shoelace icon name property

    if (state === 'loading') {
      const spinner = document.createElement('sl-spinner');
      spinner.style.fontSize = '1em'; // Adjust size if needed
      spinner.style.setProperty('--indicator-color', 'currentColor');
      spinner.style.setProperty('--track-width', '2px');
      button.appendChild(spinner);
    } else if (state === 'playing') {
      button.name = 'stop-circle'; // Use Shoelace name for stop icon
    } else { // idle or error state
      this.resetButtonState(button, button.dataset.originalIconName || 'volume-up');
    }
  }

  resetButtonState(button, originalIconName) {
    button.dataset.ttsState = 'idle';
    button.disabled = false;
    // Clear existing content (icon/spinner)
    while (button.firstChild) {
        button.removeChild(button.firstChild);
    }
    button.name = originalIconName; // Restore original icon name
    // Clean up the stored original name attribute after restoring
    delete button.dataset.originalIconName;
  }

  disconnect() {
    // Stop playback and clean up when the controller disconnects
    this.stopPlayback();
  }
}
