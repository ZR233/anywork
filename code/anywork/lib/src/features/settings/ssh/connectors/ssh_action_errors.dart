import '../../connectors/settings_failure_text.dart';
import '../../state/settings_action.dart';

List<String> sshActionErrors(SettingsAction? action) => [
  if (action?.error case final error?) settingsFailureText(error),
  if (action?.observationError case final error?) settingsFailureText(error),
  if (action?.operation?.error case final error?) settingsFailureText(error),
  if (action?.operation?.evidenceError case final error?) settingsFailureText(error),
].toSet().toList();
