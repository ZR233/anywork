#include "studio_instance.h"

#include <cstdio>
#include <cstring>

#if defined(_WIN32)
#include <windows.h>
#include <vector>
#else
#include <dlfcn.h>
#include <glib.h>
#endif

namespace anywork {

DesktopInstanceBootstrap::DesktopInstanceBootstrap() {
#if !defined(ANYWORK_DEMO)
#if defined(_WIN32)
  std::vector<wchar_t> executable(32768);
  const DWORD length = GetModuleFileNameW(
      nullptr, executable.data(), static_cast<DWORD>(executable.size()));
  if (length == 0 || length >= executable.size()) return;
  const std::wstring path(executable.data(), length);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return;
  HMODULE library = LoadLibraryExW(
      (path.substr(0, separator + 1) + L"pl_studio_bridge.dll").c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (library != nullptr) {
    claim_ = reinterpret_cast<ClaimFunction>(
        GetProcAddress(library, "anywork_desktop_instance_claim"));
    report_ = reinterpret_cast<ReportFunction>(
        GetProcAddress(library, "anywork_desktop_instance_report"));
  }
#else
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", &error);
  if (executable == nullptr) return;
  g_autofree gchar* directory = g_path_get_dirname(executable);
  g_autofree gchar* path = g_build_filename(
      directory, "lib", "libpl_studio_bridge.so", nullptr);
  void* library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (library != nullptr) {
    claim_ = reinterpret_cast<ClaimFunction>(dlsym(library, "anywork_desktop_instance_claim"));
    report_ = reinterpret_cast<ReportFunction>(dlsym(library, "anywork_desktop_instance_report"));
  }
#endif
  if (claim_ == nullptr || report_ == nullptr) {
    claim_ = nullptr;
    report_ = nullptr;
    std::fputs("anywork-instance event=claim_failed code=packaged_bridge_unavailable\n", stderr);
  }
#endif
}

InstanceClaim DesktopInstanceBootstrap::Claim() {
#if defined(ANYWORK_DEMO)
  return InstanceClaim::Primary;
#else
  if (claim_ == nullptr) return InstanceClaim::Failed;
  const NativeInstanceClaim claim = claim_();
  if (claim.key[64] != '\0' || std::strlen(claim.key) != 64) {
    return InstanceClaim::Failed;
  }
  for (size_t index = 0; index < 64; ++index) {
    const char digit = claim.key[index];
    if (!((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f'))) {
      return InstanceClaim::Failed;
    }
  }
  key_.assign(claim.key, 64);
  switch (claim.status) {
    case 0: return InstanceClaim::Primary;
    case 1: return InstanceClaim::Occupied;
    default: return InstanceClaim::Failed;
  }
#endif
}

void DesktopInstanceBootstrap::Report(InstanceEvent event) const {
  if (report_ != nullptr) report_(static_cast<uint32_t>(event));
}

}  // namespace anywork
