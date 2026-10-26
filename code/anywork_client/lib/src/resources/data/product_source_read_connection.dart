import '../domain/closing.dart';
import '../domain/product_source.dart';
import '../domain/read_primitives.dart';

abstract interface class ProductSourceStatusReadConnection {
  Future<ProductSourceStatusReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
