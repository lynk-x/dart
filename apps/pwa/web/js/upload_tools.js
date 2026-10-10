// Direct-to-R2 uploads with progress and a stall-based timeout.
//
// fetch() can't report upload progress, and a fixed total timeout (the old 60 s) kills a large
// video that is still moving on a slow mobile connection. XMLHttpRequest reports upload progress,
// and here the only timeout is "no bytes sent for stallMs" — so a slow-but-alive upload
// continues, while a dead connection fails fast and the caller retries with a fresh presigned URL.

// After the last byte is sent no more progress events fire while R2 finalizes the object, so the
// stall timer would misfire on a completed upload — wait for the response on its own timer.
const RESPONSE_WAIT_MS = 60000;

window.lynkUploadTools = {
  // PUTs [bytes] to a presigned [url]. Resolves with the HTTP status (the caller decides what
  // counts as success); rejects with Error('stalled' | 'network' | 'aborted') when the transfer
  // itself fails. [onProgress] receives 0..1 as bytes leave the device.
  putWithProgress(url, bytes, contentType, onProgress, stallMs) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      let stallTimer = null;
      let settled = false;

      const finish = (fn, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(stallTimer);
        fn(value);
      };
      const armTimer = (ms) => {
        clearTimeout(stallTimer);
        stallTimer = setTimeout(() => {
          finish(reject, new Error('stalled'));
          xhr.abort();
        }, ms);
      };

      xhr.open('PUT', url);
      xhr.setRequestHeader('Content-Type', contentType);
      xhr.upload.onprogress = (event) => {
        armTimer(stallMs);
        if (onProgress && event.lengthComputable && event.total > 0) {
          onProgress(event.loaded / event.total);
        }
      };
      xhr.upload.onload = () => armTimer(RESPONSE_WAIT_MS);
      xhr.onload = () => finish(resolve, xhr.status);
      xhr.onerror = () => finish(reject, new Error('network'));
      xhr.onabort = () => finish(reject, new Error('aborted'));

      armTimer(stallMs);
      xhr.send(bytes);
    });
  },
};
