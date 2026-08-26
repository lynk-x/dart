// Browser-native camera stream helper for Flutter Web (PWA).
// Manages getUserMedia stream lifecycle, mirror transforms, video constraints,
// capture (capturePhoto) and clip recording (startRecording/stopRecording).

window.flutterCameraStream = {
  stream: null,
  videoElement: null,
  mediaRecorder: null,
  recordedChunks: [],
  activeDeviceId: null,
  activeFacingMode: "environment",
  recordCanvas: null,
  recordAnimFrameId: null,

  isFrontFacing() {
    return this.activeFacingMode === "user";
  },

  async start(elementId, facingMode = "environment") {
    let el = document.getElementById(elementId);
    
    // Poll for DOM element insertion (handles Flutter Web HtmlElementView async mounting)
    for (let attempts = 0; attempts < 15 && !el; attempts++) {
      await new Promise(r => setTimeout(r, 50));
      el = document.getElementById(elementId) || document.querySelector(`video[id="${elementId}"]`);
    }

    if (!el) {
      console.error(`flutterCameraStream.start: element #${elementId} not found`);
      return false;
    }
    this.videoElement = el;
    this.activeFacingMode = facingMode;

    const success = await this._initStreamWithFacing(facingMode);
    if (!success && facingMode !== "user") {
      console.warn("Falling back to user facing camera...");
      this.activeFacingMode = "user";
      return await this._initStreamWithFacing("user");
    }
    return success;
  },

  async _initStreamWithFacing(facingMode) {
    this.stop();

    const constraints = {
      video: {
        facingMode: { ideal: facingMode },
        width: { ideal: 1920 },
        height: { ideal: 1080 }
      }
    };

    try {
      this.stream = await navigator.mediaDevices.getUserMedia(constraints);
      this.videoElement.srcObject = this.stream;
      this.videoElement.oncontextmenu = (e) => e.preventDefault();
      await this.videoElement.play();

      const videoTrack = this.stream.getVideoTracks()[0];
      if (videoTrack) {
        const settings = videoTrack.getSettings();
        this.activeDeviceId = settings.deviceId || null;
      }
      return true;
    } catch (e) {
      console.error(`getUserMedia failed for facingMode=${facingMode}:`, e);
      return false;
    }
  },

  async switchCamera() {
    const targetFacing = this.activeFacingMode === "user" ? "environment" : "user";
    const success = await this._initStreamWithFacing(targetFacing);
    if (success) {
      this.activeFacingMode = targetFacing;
    }
    return success;
  },

  stop() {
    this.stopRecordingLoop();
    if (this.stream) {
      this.stream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {}
      });
      this.stream = null;
    }
    if (this.recordStream) {
      this.recordStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {}
      });
      this.recordStream = null;
    }
    if (this.audioStream) {
      this.audioStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {}
      });
      this.audioStream = null;
    }
    if (this.videoElement) {
      try {
        this.videoElement.pause();
        this.videoElement.srcObject = null;
        this.videoElement.removeAttribute("src");
        this.videoElement.load();
      } catch (e) {}
    }
    this.activeDeviceId = null;
  },

  getZoomCapabilities() {
    if (!this.stream) return null;
    const videoTrack = this.stream.getVideoTracks()[0];
    if (!videoTrack || typeof videoTrack.getCapabilities !== "function") return null;

    const capabilities = videoTrack.getCapabilities();
    if (!capabilities.zoom) return null;

    const settings = videoTrack.getSettings();
    return {
      min: capabilities.zoom.min,
      max: capabilities.zoom.max,
      step: capabilities.zoom.step,
      current: settings.zoom || capabilities.zoom.min
    };
  },

  async setZoom(zoomValue) {
    if (!this.stream) return false;
    const videoTrack = this.stream.getVideoTracks()[0];
    if (!videoTrack || typeof videoTrack.applyConstraints !== "function") return false;

    try {
      await videoTrack.applyConstraints({
        advanced: [{ zoom: zoomValue }]
      });
      return true;
    } catch (e) {
      console.error("Failed to set zoom:", e);
      return false;
    }
  },

  async toggleTorch(enabled) {
    if (!this.stream) return false;
    const videoTrack = this.stream.getVideoTracks()[0];
    if (!videoTrack || typeof videoTrack.applyConstraints !== "function") return false;

    try {
      await videoTrack.applyConstraints({
        advanced: [{ torch: enabled }]
      });
      return true;
    } catch (e) {
      console.error("Failed to toggle torch:", e);
      return false;
    }
  },

  // Snapshots the current video frame to a JPEG blob, returns an object URL.
  // Caller (Dart) is responsible for revoking the URL once the blob has been
  // read, via revokeObjectUrl().
  async capturePhoto() {
    if (!this.videoElement || this.videoElement.readyState < this.videoElement.HAVE_CURRENT_DATA) {
      console.error("capturePhoto: video not ready.");
      return null;
    }

    const width = this.videoElement.videoWidth;
    const height = this.videoElement.videoHeight;
    if (width === 0 || height === 0) {
      console.error("capturePhoto: video has no dimensions.");
      return null;
    }

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (this.isFrontFacing()) {
      ctx.translate(width, 0);
      ctx.scale(-1, 1);
    }
    ctx.drawImage(this.videoElement, 0, 0, width, height);

    return new Promise((resolve) => {
      canvas.toBlob((blob) => {
        if (!blob) {
          resolve(null);
          return;
        }
        const url = URL.createObjectURL(blob);
        resolve(this._registerObjectUrlAutoRevoke(url));
      }, "image/jpeg", 0.9);
    });
  },

  // MediaRecorder's supported mimeType is browser-dependent (webm on
  // Chrome/Firefox, mp4 on Safari) — probed at call time rather than
  // hardcoded, since forcing an unsupported type throws synchronously.
  _pickRecorderMimeType() {
    const candidates = [
      "video/webm;codecs=vp9",
      "video/webm;codecs=vp8",
      "video/webm",
      "video/mp4",
    ];
    for (const type of candidates) {
      if (window.MediaRecorder && MediaRecorder.isTypeSupported(type)) {
        return type;
      }
    }
    return "";
  },

  stopRecordingLoop() {
    if (this.mediaRecorder) {
      try {
        if (this.mediaRecorder.state !== "inactive") {
          this.mediaRecorder.stop();
        }
      } catch (e) {}
      this.mediaRecorder = null;
    }
    if (this.recordAnimFrameId) {
      cancelAnimationFrame(this.recordAnimFrameId);
      this.recordAnimFrameId = null;
    }
    this.recordCanvas = null;
    if (this.recordStream) {
      this.recordStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {}
      });
      this.recordStream = null;
    }
    if (this.audioStream) {
      this.audioStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {}
      });
      this.audioStream = null;
    }
  },

  async startRecording() {
    if (!this.stream) return false;
    if (this.mediaRecorder && this.mediaRecorder.state === "recording") return false;

    let recordStream = this.stream;

    // Acquire microphone audio track for video recording if available
    try {
      const audioStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const audioTrack = audioStream.getAudioTracks()[0];
      if (audioTrack) {
        this.audioStream = audioStream;
        recordStream = recordStream.clone();
        recordStream.addTrack(audioTrack);
      }
    } catch (e) {
      console.warn("Recording video without audio track (mic permission pending or unavailable):", e);
    }

    // For front camera, draw to canvas & capture mirrored stream so recorded video matches preview
    if (this.isFrontFacing() && this.videoElement) {
      const width = this.videoElement.videoWidth || 1280;
      const height = this.videoElement.videoHeight || 720;

      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext("2d");
      this.recordCanvas = canvas;

      const drawFrame = () => {
        if (!this.recordCanvas || !this.videoElement) return;
        if (!document.hidden && !this.videoElement.paused) {
          ctx.save();
          ctx.translate(width, 0);
          ctx.scale(-1, 1);
          ctx.drawImage(this.videoElement, 0, 0, width, height);
          ctx.restore();
        }
        this.recordAnimFrameId = requestAnimationFrame(drawFrame);
      };

      drawFrame();

      if (typeof canvas.captureStream === "function") {
        const canvasStream = canvas.captureStream(30);
        // Include audio tracks from recordStream
        recordStream.getAudioTracks().forEach(track => canvasStream.addTrack(track));
        recordStream = canvasStream;
      }
    }

    this.recordStream = recordStream;

    const mimeType = this._pickRecorderMimeType();
    try {
      this.mediaRecorder = mimeType
        ? new MediaRecorder(recordStream, { mimeType })
        : new MediaRecorder(recordStream);
    } catch (e) {
      console.error("Failed to create MediaRecorder:", e);
      this.stopRecordingLoop();
      return false;
    }

    this.recordedChunks = [];
    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data && event.data.size > 0) {
        this.recordedChunks.push(event.data);
      }
    };

    try {
      this.mediaRecorder.start();
      return true;
    } catch (e) {
      console.error("Failed to start recording:", e);
      this.stopRecordingLoop();
      return false;
    }
  },

  // Resolves with an object URL for the recorded clip once the recorder has
  // fully flushed, or null if nothing was recording.
  stopRecording() {
    return new Promise((resolve) => {
      if (!this.mediaRecorder || this.mediaRecorder.state === "inactive") {
        this.stopRecordingLoop();
        resolve(null);
        return;
      }

      const recorder = this.mediaRecorder;
      const mimeType = recorder.mimeType || "video/webm";

      recorder.onstop = () => {
        this.stopRecordingLoop();
        if (this.recordedChunks.length === 0) {
          resolve(null);
          return;
        }
        const blob = new Blob(this.recordedChunks, { type: mimeType });
        this.recordedChunks = [];
        const url = URL.createObjectURL(blob);
        resolve(this._registerObjectUrlAutoRevoke(url));
      };

      try {
        recorder.stop();
      } catch (e) {
        console.error("Failed to stop recording:", e);
        this.stopRecordingLoop();
        resolve(null);
      }
    });
  },

  _autoRevokeTimers: {},

  _registerObjectUrlAutoRevoke(url) {
    if (!url) return url;
    // Set 60-second fallback auto-revocation to prevent blob memory leaks
    this._autoRevokeTimers[url] = setTimeout(() => {
      this.revokeObjectUrl(url);
    }, 60000);
    return url;
  },

  revokeObjectUrl(url) {
    if (!url) return;
    if (this._autoRevokeTimers[url]) {
      clearTimeout(this._autoRevokeTimers[url]);
      delete this._autoRevokeTimers[url];
    }
    try {
      URL.revokeObjectURL(url);
    } catch (e) {
      console.warn("Failed to revoke object URL:", e);
    }
  }
};
