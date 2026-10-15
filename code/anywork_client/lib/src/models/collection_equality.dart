/// Compares nullable lists by their ordered elements using SDK equality.
///
/// This mirrors the value comparison required by immutable Client models and
/// keeps the model layer independent from Flutter's foundation library.
bool listEquals<T>(List<T>? left, List<T>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length)
    return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
