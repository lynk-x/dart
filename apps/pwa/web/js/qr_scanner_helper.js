window.flutterQrScanner = {
  stream: null,
  videoElement: null,
  canvasElement: null,
  canvasContext: null,
  scanning: false,
  callback: null,
  scanInterval: 150,

  setScanInterval(ms) {
    this.scanInterval = ms;
  },

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

  async start(videoElementId, onScanCallback) {
    this.callback = onScanCallback;
    this.facingMode = "environment";
    
    // Wait for the video element using MutationObserver
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
        console.warn("Failed to get environment camera, trying fallback to default video source:", err);
        this.stream = await navigator.mediaDevices.getUserMedia({
          video: true,
          audio: false
        });
      }

      this.videoElement.srcObject = this.stream;
      this.videoElement.setAttribute("playsinline", "true");
      this.videoElement.setAttribute("autoplay", "true");
      this.videoElement.setAttribute("muted", "true");
      
      // Try playing the video
      await this.videoElement.play();
      this.scanning = true;
      
      this.canvasElement = document.createElement("canvas");
      this.canvasContext = this.canvasElement.getContext("2d", { willReadFrequently: true });
      
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

  async switchCamera() {
    if (!this.stream) return false;

    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const videoDevices = devices.filter(d => d.kind === 'videoinput');
      
      if (videoDevices.length <= 1) {
        console.warn("Only one camera available, cannot switch.");
        return false;
      }

      // Find the current active video track's deviceId
      const activeTrack = this.stream.getVideoTracks()[0];
      const currentDeviceId = activeTrack ? activeTrack.getSettings().deviceId : null;

      let nextDevice = null;
      if (currentDeviceId) {
        const currentIndex = videoDevices.findIndex(d => d.deviceId === currentDeviceId);
        if (currentIndex !== -1) {
          // Select the next camera in the list
          const nextIndex = (currentIndex + 1) % videoDevices.length;
          nextDevice = videoDevices[nextIndex];
        }
      }

      if (!nextDevice) {
        nextDevice = videoDevices[0];
      }

      // Stop current stream tracks
      const tracks = this.stream.getTracks();
      tracks.forEach(track => track.stop());

      // Start new stream with selected deviceId
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
      
      // Fallback to toggle facingMode in case exact deviceId constraint failed
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

  async tick() {
    if (!this.scanning) return;

    try {
      if (this.videoElement && this.videoElement.readyState === this.videoElement.HAVE_ENOUGH_DATA) {
        const width = this.videoElement.videoWidth;
        const height = this.videoElement.videoHeight;
        
        if (width > 0 && height > 0) {
          if (this.canvasElement.width !== width || this.canvasElement.height !== height) {
            this.canvasElement.width = width;
            this.canvasElement.height = height;
          }
          this.canvasContext.drawImage(this.videoElement, 0, 0, width, height);
          
          const imageData = this.canvasContext.getImageData(0, 0, width, height);
          let decodedText = null;

          // Try decoding using ZXing (supports QR codes and all 1D barcode formats)
          if (window.ZXing) {
            if (!this.zxingReader) {
              const hints = new Map();
              hints.set(ZXing.DecodeHintType.POSSIBLE_FORMATS, [
                ZXing.BarcodeFormat.QR_CODE,
                ZXing.BarcodeFormat.CODE_128
              ]);
              hints.set(ZXing.DecodeHintType.TRY_HARDER, true);
              this.zxingReader = new ZXing.BrowserMultiFormatReader(hints);
            }
            try {
              const luminanceSource = new ZXing.HTMLCanvasElementLuminanceSource(this.canvasElement);
              const binarizer = new ZXing.HybridBinarizer(luminanceSource);
              const bitmap = new ZXing.BinaryBitmap(binarizer);
              const result = this.zxingReader.decodeBitmap(bitmap);
              if (result) {
                decodedText = result.getText ? result.getText() : result.text;
              }
            } catch (e) {
              // Not found in this frame
            }
          }

          // Fallback to jsQR if ZXing did not find a code or is not loaded
          if (!decodedText && window.jsQR) {
            try {
              const code = window.jsQR(imageData.data, imageData.width, imageData.height, {
                inversionAttempts: "dontInvert",
              });
              if (code && code.data) {
                decodedText = code.data;
              }
            } catch (jsqrErr) {
              // jsQR error
            }
          }

          if (decodedText) {
            if (this.callback) {
              try {
                this.callback(decodedText);
              } catch (err) {
                console.error("Error in Dart callback:", err);
              }
            }
          }
        }
      }
    } catch (e) {
      console.error("Error during scanner tick frame processing:", e);
    } finally {
      if (this.scanning) {
        setTimeout(() => {
          requestAnimationFrame(() => this.tick());
        }, this.scanInterval);
      }
    }
  }
};
