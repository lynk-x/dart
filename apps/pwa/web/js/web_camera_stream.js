// Shared raw getUserMedia camera-stream layer for Flutter Web.
// Owns stream lifecycle (start/stop/switchCamera/toggleTorch) plus frame
// capture (capturePhoto) and clip recording (startRecording/stopRecording).
// qr_scanner_helper.js wraps this for its own decode loop; the photo/video
// capture screen (web_camera_capture_web.dart) calls it directly.
window.flutterCameraStream = {
  stream: null,
  videoElement: null,
  facingMode: "environment",
  mediaRecorder: null,
  recordedChunks: [],

  findVideoElement(id) {
    let el = document.getElementById(id);
    if (el) return el;

    const search = (root, targetId) => {
      if (!root) return null;
      if (root.id === targetId || (root.tagName && root.tagName.toLowerCase() === 'video' && (!targetId || root.id === targetId))) {
        return root;
      }

      if (root.shadowRoot) {
        const found = search(root.shadowRoot, targetId);
        if (found) return found;
      }

      const children = root.childNodes || [];
      for (let i = 0; i < children.length; i++) {
        const found = search(children[i], targetId);
        if (found) return found;
      }
      return null;
    };

    let found = search(document, id);
    if (found) return found;

    return search(document, null);
  },

  waitForElement(id, timeoutMs = 2500) {
    return new Promise((resolve) => {
      const startTime = Date.now();

      const check = () => {
        const el = this.findVideoElement(id);
        if (el) {
          resolve(el);
          return;
        }

        if (Date.now() - startTime > timeoutMs) {
          console.warn("waitForElement timed out waiting for video element:", id);
          resolve(null);
          return;
        }

        setTimeout(check, 50);
      };

      check();
    });
  },

  async start(videoElementId, facingMode = "environment") {
    this.facingMode = facingMode;

    this.videoElement = await this.waitForElement(videoElementId);

    if (!this.videoElement) {
      console.error("Video element not found after waiting:", videoElementId);
      return false;
    }

    try {
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: this.facingMode } },
          audio: false
        });
      } catch (err) {
        console.warn("Failed to get preferred-facing camera, trying fallback to default video source:", err);
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: true,
          audio: false
        });
      }

      this.videoElement.srcObject = this.stream;
      this.videoElement.setAttribute("playsinline", "true");
      this.videoElement.setAttribute("autoplay", "true");
      this.videoElement.setAttribute("muted", "true");
      this.videoElement.style.objectFit = "cover";
      this.videoElement.style.width = "100%";
      this.videoElement.style.height = "100%";

      await this.videoElement.play();
      return true;
    } catch (e) {
      console.error("Error starting camera:", e);
      return false;
    }
  },

  stop() {
    if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
      try {
        this.mediaRecorder.stop();
      } catch (e) {
        console.warn("Error stopping in-flight recorder during stop():", e);
      }
    }
    this.mediaRecorder = null;
    this.recordedChunks = [];

    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    if (this.videoElement) {
      this.videoElement.srcObject = null;
    }
  },

  async switchCamera() {
    if (!this.stream) return false;

    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const videoDevices = devices.filter(d => d.kind === 'videoinput');

      if (videoDevices.length <= 1) {
        console.warn("Only one camera available, cannot switch.");
        return false;
      }

      const activeTrack = this.stream.getVideoTracks()[0];
      const currentDeviceId = activeTrack ? activeTrack.getSettings().deviceId : null;

      let nextDevice = null;
      if (currentDeviceId) {
        const currentIndex = videoDevices.findIndex(d => d.deviceId === currentDeviceId);
        if (currentIndex !== -1) {
          const nextIndex = (currentIndex + 1) % videoDevices.length;
          nextDevice = videoDevices[nextIndex];
        }
      }

      if (!nextDevice) {
        nextDevice = videoDevices[0];
      }

      const tracks = this.stream.getTracks();
      tracks.forEach(track => track.stop());

      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { deviceId: { exact: nextDevice.deviceId } },
        audio: false
      });

      if (this.videoElement) {
        this.videoElement.srcObject = this.stream;
        await this.videoElement.play();
        return true;
      }
    } catch (err) {
      console.error("Failed to switch camera by deviceId:", err);

      this.facingMode = this.facingMode === "user" ? "environment" : "user";
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: this.facingMode } },
          audio: false
        });
        if (this.videoElement) {
          this.videoElement.srcObject = this.stream;
          await this.videoElement.play();
          return true;
        }
      } catch (fallbackErr) {
        console.error("Critical: Fallback camera switch failed:", fallbackErr);
      }
    }
    return false;
  },

  // Whether the currently active camera is front-facing (selfie/"user").
  // Reads the live track's own reported facingMode when the browser
  // exposes it — this.facingMode alone is unreliable, since switchCamera's
  // primary deviceId-cycling path never updates it (only its facingMode
  // fallback path does). Falls back to the stored value only when the
  // track itself doesn't report a facingMode (getSettings().facingMode is
  // undefined on some browsers/devices).
  isFrontFacing() {
    if (!this.stream) return false;
    const track = this.stream.getVideoTracks()[0];
    const settings = track && track.getSettings ? track.getSettings() : {};
    if (settings.facingMode) {
      return settings.facingMode === "user";
    }
    return this.facingMode === "user";
  },

  // Returns {min, max, step} if the active track supports optical/digital
  // zoom via the standard MediaStreamTrack constraint, or null if it
  // doesn't — zoom capability is inconsistent across browsers/devices
  // (notably weak on Firefox and some Android Chrome builds), same caveat
  // as torch above.
  getZoomCapabilities() {
    if (!this.stream) return null;
    const track = this.stream.getVideoTracks()[0];
    if (!track || !track.getCapabilities) return null;
    const capabilities = track.getCapabilities();
    if (!capabilities.zoom) return null;
    return {
      min: capabilities.zoom.min,
      max: capabilities.zoom.max,
      step: capabilities.zoom.step || 0.1,
    };
  },

  async setZoom(value) {
    if (!this.stream) return false;
    const videoTrack = this.stream.getVideoTracks()[0];
    if (!videoTrack) return false;

    try {
      await videoTrack.applyConstraints({
        advanced: [{ zoom: value }]
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
    if (!videoTrack) return false;

    const capabilities = videoTrack.getCapabilities ? videoTrack.getCapabilities() : {};
    if (!capabilities.torch) {
      console.warn("Torch/Flashlight is not supported on this device/browser.");
      return false;
    }

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
        resolve(URL.createObjectURL(blob));
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

  startRecording() {
    if (!this.stream) return false;
    if (this.mediaRecorder && this.mediaRecorder.state === "recording") return false;

    const mimeType = this._pickRecorderMimeType();
    try {
      this.mediaRecorder = mimeType
        ? new MediaRecorder(this.stream, { mimeType })
        : new MediaRecorder(this.stream);
    } catch (e) {
      console.error("Failed to create MediaRecorder:", e);
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
      return false;
    }
  },

  // Resolves with an object URL for the recorded clip once the recorder has
  // fully flushed, or null if nothing was recording.
  stopRecording() {
    return new Promise((resolve) => {
      if (!this.mediaRecorder || this.mediaRecorder.state === "inactive") {
        resolve(null);
        return;
      }

      const recorder = this.mediaRecorder;
      const mimeType = recorder.mimeType || "video/webm";

      recorder.onstop = () => {
        if (this.recordedChunks.length === 0) {
          resolve(null);
          return;
        }
        const blob = new Blob(this.recordedChunks, { type: mimeType });
        this.recordedChunks = [];
        resolve(URL.createObjectURL(blob));
      };

      try {
        recorder.stop();
      } catch (e) {
        console.error("Failed to stop recording:", e);
        resolve(null);
      }
    });
  },

  revokeObjectUrl(url) {
    try {
      URL.revokeObjectURL(url);
    } catch (e) {
      console.warn("Failed to revoke object URL:", e);
    }
  },
};
