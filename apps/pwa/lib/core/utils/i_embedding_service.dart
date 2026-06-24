abstract class IEmbeddingService {
  bool get isReady;
  void init();
  void processMessage(String messageId, String text);
}
