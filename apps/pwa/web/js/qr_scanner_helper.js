// Thin decode-loop wrapper around the shared window.flutterCameraStream
// (web_camera_stream.js), which owns the actual getUserMedia
// start/stop/switchCamera/toggleTorch lifecycle. Load order matters:
// web_camera_stream.js must be included before this file.
window.flutterQrScanner = {
  canvasElement: null,
  canvasContext: null,
  scanning: false,
  callback: null,
  scanInterval: 150,

  setScanInterval(ms) {
    this.scanInterval = ms;
  },

  get videoElement() {
    return window.flutterCameraStream.videoElement;
  },

  async start(videoElementId, onScanCallback) {
    this.callback = onScanCallback;

    const started = await window.flutterCameraStream.start(videoElementId, "environment");
    if (!started) return false;

    this.scanning = true;
    this.canvasElement = document.createElement("canvas");
    this.canvasContext = this.canvasElement.getContext("2d", { willReadFrequently: true });

    requestAnimationFrame(() => this.tick());
    return true;
  },

  stop() {
    this.scanning = false;
    window.flutterCameraStream.stop();
  },

  async switchCamera() {
    return window.flutterCameraStream.switchCamera();
  },

  async toggleTorch(enabled) {
    return window.flutterCameraStream.toggleTorch(enabled);
  },

  async tick() {
    if (!this.scanning) return;

    try {
      const videoElement = this.videoElement;
      if (videoElement && videoElement.readyState === videoElement.HAVE_ENOUGH_DATA) {
        const width = videoElement.videoWidth;
        const height = videoElement.videoHeight;
        
        if (width > 0 && height > 0) {
          if (this.canvasElement.width !== width || this.canvasElement.height !== height) {
            this.canvasElement.width = width;
            this.canvasElement.height = height;
          }
          this.canvasContext.drawImage(videoElement, 0, 0, width, height);
          
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
