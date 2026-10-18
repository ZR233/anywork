#include "utils.h"

#include <windows.h>

#include <cstdio>
#include <iterator>

void LogNativeLifecycle(const char* event, UINT message, WPARAM wparam,
                        LPARAM lparam) {
  wchar_t path[32768];
  const DWORD length = GetEnvironmentVariableW(
      L"ANYWORK_NATIVE_LIFECYCLE_LOG", path,
      static_cast<DWORD>(std::size(path)));
  if (length == 0 || length >= std::size(path)) {
    return;
  }

  HANDLE file = CreateFileW(path, FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  SYSTEMTIME timestamp;
  GetSystemTime(&timestamp);
  char line[256];
  const int bytes = sprintf_s(
      line,
      "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ pid=%lu tid=%lu event=%s "
      "message=%u wparam=%llu lparam=%lld\r\n",
      timestamp.wYear, timestamp.wMonth, timestamp.wDay, timestamp.wHour,
      timestamp.wMinute, timestamp.wSecond, timestamp.wMilliseconds,
      GetCurrentProcessId(), GetCurrentThreadId(), event, message,
      static_cast<unsigned long long>(wparam), static_cast<long long>(lparam));
  if (bytes > 0) {
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(bytes), &written, nullptr);
  }
  CloseHandle(file);
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
