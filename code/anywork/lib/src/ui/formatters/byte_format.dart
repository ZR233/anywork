/// Attachment byte display, preserving the existing 1024-based B / KB / MB
/// labels. It is not a token formatter and does not alter the exact byte count.
String formatBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
