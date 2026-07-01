window.flutterQrScanner = {
  stream: null,
  videoElement: null,
  canvasElement: null,
  canvasContext: null,
  scanning: false,
  callback: null,

  async start(videoElementId, onScanCallback) {
    this.callback = onScanCallback;
    
    // Poll for the video element to exist in the DOM (up to 2 seconds)
    let attempts = 0;
    this.videoElement = null;
    while (!this.videoElement && attempts < 40) {
      this.videoElement = document.getElementById(videoElementId);
      if (this.videoElement) break;
      await new Promise(resolve => setTimeout(resolve, 50));
      attempts++;
    }

    if (!this.videoElement) {
      console.error("Video element not found after polling:", videoElementId);
      return false;
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
        audio: false
      });
      this.videoElement.srcObject = this.stream;
      this.videoElement.setAttribute("playsinline", "true");
      this.videoElement.setAttribute("autoplay", "true");
      this.videoElement.setAttribute("muted", "true");
      
      // Try playing the video
      await this.videoElement.play();
      this.scanning = true;
      
      this.canvasElement = document.createElement("canvas");
      this.canvasContext = this.canvasElement.getContext("2d");
      
      requestAnimationFrame(() => this.tick());
      return true;
    } catch (e) {
      console.error("Error starting camera:", e);
      return false;
    }
  },

  stop() {
    this.scanning = false;
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    if (this.videoElement) {
      this.videoElement.srcObject = null;
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

  tick() {
    if (!this.scanning) return;

    if (this.videoElement && this.videoElement.readyState === this.videoElement.HAVE_ENOUGH_DATA) {
      const width = this.videoElement.videoWidth;
      const height = this.videoElement.videoHeight;
      this.canvasElement.width = width;
      this.canvasElement.height = height;
      this.canvasContext.drawImage(this.videoElement, 0, 0, width, height);
      
      const imageData = this.canvasContext.getImageData(0, 0, width, height);
      if (window.jsQR) {
        const code = window.jsQR(imageData.data, imageData.width, imageData.height, {
          inversionAttempts: "dontInvert",
        });
        if (code && code.data) {
          if (this.callback) {
            try {
              this.callback(code.data);
            } catch (err) {
              console.error("Error in Dart callback:", err);
            }
          }
        }
      } else {
        console.warn("jsQR is not loaded yet.");
      }
    }
    
    if (this.scanning) {
      setTimeout(() => {
        requestAnimationFrame(() => this.tick());
      }, 150); // Scan ~6-7 times per second
    }
  }
};
