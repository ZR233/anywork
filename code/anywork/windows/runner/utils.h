#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <windows.h>

#include <string>
#include <vector>

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Appends one line to the diagnostic file named by
// ANYWORK_NATIVE_LIFECYCLE_LOG. The write is best effort and does nothing when
// the variable is unset or cannot be opened. Kept outside the window class so
// tray and lifecycle events share the same log format.
void LogNativeLifecycle(const char* event, UINT message, WPARAM wparam,
                        LPARAM lparam);

#endif  // RUNNER_UTILS_H_
