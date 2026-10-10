// Client-side image downscaling for forum uploads: phone photos are routinely 4-8 MB, which is a
// lot of data to upload (and later download into the media grid) on metered mobile connections.
// Used by ForumMediaCubit via core/utils/image_resizer.dart.

window.lynkImageTools = {
  // Fits the image inside a maxEdge x maxEdge box (never upscales) and re-encodes it as JPEG.
  // Resolves null when the browser can't decode the input (e.g. HEIC outside Safari) so the
  // caller can upload the original unchanged. EXIF orientation is applied, which also drops
  // EXIF metadata (including GPS location) from the re-encoded copy.
  async resizeToJpeg(bytes, maxEdge, quality) {
    try {
      const bitmap = await createImageBitmap(new Blob([bytes]), { imageOrientation: 'from-image' });
      const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
      const width = Math.max(1, Math.round(bitmap.width * scale));
      const height = Math.max(1, Math.round(bitmap.height * scale));

      const canvas = typeof OffscreenCanvas !== 'undefined'
        ? new OffscreenCanvas(width, height)
        : Object.assign(document.createElement('canvas'), { width, height });
      const ctx = canvas.getContext('2d');
      // JPEG has no alpha channel — flatten transparent PNGs onto white rather than black.
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, width, height);
      ctx.drawImage(bitmap, 0, 0, width, height);
      bitmap.close();

      const blob = canvas.convertToBlob
        ? await canvas.convertToBlob({ type: 'image/jpeg', quality })
        : await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
      return blob ? new Uint8Array(await blob.arrayBuffer()) : null;
    } catch (_) {
      return null;
    }
  },

  // Grabs a still frame from a video for use as its grid thumbnail, scaled to fit maxEdge and
  // encoded as JPEG. [source] is a blob:/http URL string (preferred — no copy of the video) or a
  // Uint8Array of the file. Resolves null when the browser can't decode the video (e.g. HEVC .mov
  // outside Safari) so the caller can fall back to no thumbnail.
  async videoPosterJpeg(source, maxEdge, quality) {
    let objectUrl = null;
    const video = document.createElement('video');
    try {
      const url = typeof source === 'string' ? source : (objectUrl = URL.createObjectURL(new Blob([source])));
      video.muted = true;
      video.playsInline = true;
      video.preload = 'auto';
      video.src = url;

      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('timeout')), 8000);
        video.onloadeddata = () => { clearTimeout(timer); resolve(); };
        video.onerror = () => { clearTimeout(timer); reject(new Error('decode')); };
      });

      // A frame a little way in avoids the black/fade-in first frame most clips start with.
      const target = Math.min(1, (isFinite(video.duration) ? video.duration : 0) * 0.1);
      if (target > 0) {
        await new Promise((resolve) => {
          const timer = setTimeout(resolve, 3000);
          video.onseeked = () => { clearTimeout(timer); resolve(); };
          video.currentTime = target;
        });
      }

      if (!video.videoWidth || !video.videoHeight) return null;
      const scale = Math.min(1, maxEdge / Math.max(video.videoWidth, video.videoHeight));
      const width = Math.max(1, Math.round(video.videoWidth * scale));
      const height = Math.max(1, Math.round(video.videoHeight * scale));
      const canvas = Object.assign(document.createElement('canvas'), { width, height });
      canvas.getContext('2d').drawImage(video, 0, 0, width, height);

      const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
      return blob ? new Uint8Array(await blob.arrayBuffer()) : null;
    } catch (_) {
      return null;
    } finally {
      video.removeAttribute('src');
      video.load();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
  },
};
