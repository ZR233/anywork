/// Matches Rust's to_ascii_lowercase; non-ASCII code units are unchanged.
String skillNameKey(String name) => String.fromCharCodes(name.codeUnits.map((unit) =>
  unit >= 65 && unit <= 90 ? unit + 32 : unit));

bool skillNameDisabled(Iterable<String> disabled, String name) {
  final key = skillNameKey(name);
  return disabled.any((value) => skillNameKey(value) == key);
}
