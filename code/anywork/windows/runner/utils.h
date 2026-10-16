#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <cstdint>
#include <string>
#include <vector>

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Converts a UTF-8 string to UTF-16. Empty input or conversion failure yields
// an empty std::wstring; this helper never throws.
std::wstring Utf16FromUtf8(const std::string& utf8);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Host UI language used by the window title and tray labels.
bool HostUiPrefersChinese();

// Optional native lifecycle diagnostics. Same env var and single-line format as
// the previous win32_window helper; writes are best-effort and silent on error.
void LogNativeLifecycleEvent(const char* event, unsigned int message = 0,
                             uintptr_t wparam = 0, intptr_t lparam = 0);

#endif  // RUNNER_UTILS_H_
