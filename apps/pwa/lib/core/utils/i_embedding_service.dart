/// Interface for client-side message embedding computation, so cubits can
/// depend on an abstraction rather than [EmbeddingManager]'s web-worker
/// implementation directly (useful for tests/non-web targets).
abstract class IEmbeddingService {
  bool get isReady;
  void init();
  void processMessage(String messageId, String text);
}
