// File: dart/apps/pwa/web/embedding.worker.js
// Description: Web Worker to run Transformers.js client-side inference for vector embeddings.

// Import Transformers.js via ESM CDN
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2';

// Force CDN loading for model files instead of local files
env.allowLocalModels = false;

let extractor = null;

// Listen for messages from the Dart PWA client
self.onmessage = async (event) => {
  const { type, text, msgId } = event.data;

  if (type === 'init') {
    try {
      // Load the quantized multilingual embedding model (paraphrase-multilingual-MiniLM-L12-v2, ~110MB)
      extractor = await pipeline('feature-extraction', 'Xenova/paraphrase-multilingual-MiniLM-L12-v2', {
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
      const output = await extractor(text, { pooling: 'mean', normalize: true });
      const embedding = Array.from(output.data);
      self.postMessage({ type: 'embed_result', embedding, msgId });
    } catch (err) {
      self.postMessage({ type: 'error', error: err.message, msgId });
    }
  }
};
