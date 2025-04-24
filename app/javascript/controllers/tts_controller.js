import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "spinner"];

  connect() {
    this.audioPlayer = null;
    this.currentPlayingButton = null;
  }

  async play(event) {
    const messageId = this.buttonTarget.dataset.messageIdParam;
    const currentState = this.buttonTarget.dataset.ttsState || 'idle';
    const originalIconName = this.buttonTarget.name;

    if (!messageId) return;

    if (currentState === 'playing' && this.buttonTarget === this.currentPlayingButton) {
      this.stopPlayback();
      return;
    }

    if (currentState === 'loading' || (this.audioPlayer && !this.audioPlayer.paused)) {
      return;
    }

    this.stopPlayback();
    this.setButtonState('loading', originalIconName);
    this.currentPlayingButton = this.buttonTarget;

    try {
      const response = await fetch(`/messages/${messageId}/tts`);
      if (!response.ok) throw new Error(response.statusText || `HTTP error! status: ${response.status}`);
      const audioBlob = await response.blob();
      const audioUrl = URL.createObjectURL(audioBlob);
      this.audioPlayer = new Audio(audioUrl);

      this.audioPlayer.oncanplaythrough = () => {
        this.setButtonState('playing', originalIconName);
        this.audioPlayer.play();
      };
      this.audioPlayer.onended = () => {
        this.setButtonState('idle', originalIconName);
        URL.revokeObjectURL(audioUrl);
        this.audioPlayer = null;
        this.currentPlayingButton = null;
      };
      this.audioPlayer.onerror = () => {
        this.setButtonState('idle', originalIconName);
        URL.revokeObjectURL(audioUrl);
        this.audioPlayer = null;
        this.currentPlayingButton = null;
      };
      if (this.audioPlayer.readyState >= 3) {
        this.setButtonState('playing', originalIconName);
        this.audioPlayer.play();
      }
    } catch (error) {
      this.setButtonState('idle', originalIconName);
      this.audioPlayer = null;
      this.currentPlayingButton = null;
    }
  }

  stopPlayback() {
    if (this.audioPlayer && !this.audioPlayer.paused) {
      this.audioPlayer.pause();
      this.audioPlayer.currentTime = 0;
      if (this.currentPlayingButton) {
        const originalIcon = this.currentPlayingButton.dataset.originalIconName || 'volume-up';
        this.setButtonState('idle', originalIcon);
      }
      if (this.audioPlayer.src.startsWith('blob:')) {
        URL.revokeObjectURL(this.audioPlayer.src);
      }
    }
    this.audioPlayer = null;
    this.currentPlayingButton = null;
  }

  setButtonState(state, originalIconName) {
    this.buttonTarget.dataset.ttsState = state;
    if (state === 'loading') {
      this.buttonTarget.classList.add('hidden');
      this.spinnerTarget.classList.remove('hidden');
      if (!this.buttonTarget.dataset.originalIconName) {
        this.buttonTarget.dataset.originalIconName = originalIconName;
      }
      this.buttonTarget.name = '';
    } else if (state === 'playing') {
      this.buttonTarget.classList.remove('hidden');
      this.spinnerTarget.classList.add('hidden');
      this.buttonTarget.name = 'stop-circle';
    } else { // idle
      this.buttonTarget.classList.remove('hidden');
      this.buttonTarget.disabled = false;
      this.spinnerTarget.classList.add('hidden');
      this.buttonTarget.name = originalIconName;
      delete this.buttonTarget.dataset.originalIconName;
    }
  }

  disconnect() {
    this.stopPlayback();
  }
}
