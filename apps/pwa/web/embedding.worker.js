// File: dart/apps/pwa/web/embedding.worker.js
// Description: Web Worker to run Transformers.js client-side inference for vector embeddings.

// Import Transformers.js via ESM CDN
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers';

// Force remote loading for model files instead of local files, from our own
// R2-hosted mirror at a short, project-owned path rather than
// huggingface.co — removes the runtime dependency on a third-party CDN and
// a community model re-upload we don't control.
env.allowLocalModels = false;
env.remoteHost = 'https://cdn.lynk-x.app/';
env.remotePathTemplate = 'models/granite-embedding-97m/';

let extractor = null;

// Listen for messages from the Dart PWA client
self.onmessage = async (event) => {
  const { type, text, msgId } = event.data;

  if (type === 'init') {
    try {
      // Load the quantized multilingual embedding model (IBM Granite 97M multilingual R2, ~94MB)
      extractor = await pipeline('feature-extraction', 'yuiseki/granite-embedding-97m-multilingual-r2-ONNX', {
        progress_callback: (data) => {
          if (data.status === 'progress') {
            self.postMessage({ type: 'progress', file: data.file, progress: data.progress });
          } else if (data.status === 'ready') {
            self.postMessage({ type: 'file_ready', file: data.file });
          }
        }
      });
      self.postMessage({ type: 'ready' });
    } catch (err) {
      self.postMessage({ type: 'error', error: err.message });
    }
  }

  if (type === 'embed') {
    if (!extractor) {
      self.postMessage({ type: 'error', error: 'Model not initialized' });
      return;
    }
    try {
      // Calculate 384-dimensional vector embedding
      const output = await extractor(text, { pooling: 'cls', normalize: true });
      const embedding = Array.from(output.data);
      self.postMessage({ type: 'embed_result', embedding, msgId });
    } catch (err) {
      self.postMessage({ type: 'error', error: err.message, msgId });
    }
  }
};
