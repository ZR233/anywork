#ifndef RUNNER_COMMON_STUDIO_INSTANCE_H_
#define RUNNER_COMMON_STUDIO_INSTANCE_H_

#include <cstdint>
#include <string>

namespace anywork {

enum class InstanceClaim { Primary, Occupied, Failed };
enum class InstanceStartup { Primary, Redirected, Failed };
enum class InstanceEvent : uint32_t {
  Redirected = 0,
  Unavailable = 1,
  EndpointFailed = 2,
  Activated = 3,
  Pending = 4,
};

// C ABI with Rust desktop_instance.rs. Caller owns the returned bytes; no heap or handle crosses
// the ABI. The DLL retains its opaque host lease until OS process termination.
struct NativeInstanceClaim {
  uint32_t status;
  char key[65];
};
static_assert(sizeof(NativeInstanceClaim) == 72, "desktop instance C ABI layout");

// Loads only the packaged bridge, before Flutter. The library reference is process-owned: it
// must remain loaded while the host lease and any later FRB tasks still refer to its state.
class DesktopInstanceBootstrap {
 public:
  DesktopInstanceBootstrap();
  InstanceClaim Claim();
  void Report(InstanceEvent event) const;
  const std::string& key() const { return key_; }

 private:
  using ClaimFunction = NativeInstanceClaim (*)();
  using ReportFunction = void (*)(uint32_t);
  ClaimFunction claim_ = nullptr;
  ReportFunction report_ = nullptr;
  std::string key_;
};

}  // namespace anywork
#endif
