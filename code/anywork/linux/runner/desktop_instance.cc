#include "desktop_instance.h"

#include <gio/gio.h>
#include <algorithm>
#include <chrono>

namespace {
struct ActivationCall {
  GMainLoop* loop;
  GDBusConnection* connection = nullptr;
  bool accepted = false;
};

gboolean cancel_call(gpointer cancellation) {
  g_cancellable_cancel(G_CANCELLABLE(cancellation));
  return G_SOURCE_CONTINUE;
}

void bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  auto* call = static_cast<ActivationCall*>(data);
  g_autoptr(GError) error = nullptr;
  call->connection = g_bus_get_finish(result, &error);
  g_main_loop_quit(call->loop);
}

void activation_finished(GObject* source, GAsyncResult* result, gpointer data) {
  auto* call = static_cast<ActivationCall*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  call->accepted = reply != nullptr;
  g_main_loop_quit(call->loop);
}
}

std::string InstanceApplicationId(const std::string& key) {
  return key.empty() ? APPLICATION_ID : std::string(APPLICATION_ID) + ".d" + key;
}

anywork::InstanceStartup PrepareDesktopInstance(anywork::DesktopInstanceBootstrap& bootstrap) {
  using Clock = std::chrono::steady_clock;
  const auto deadline = Clock::now() + std::chrono::seconds(10);
  auto claim = bootstrap.Claim();
  if (claim == anywork::InstanceClaim::Primary) return anywork::InstanceStartup::Primary;
  if (claim == anywork::InstanceClaim::Failed) return anywork::InstanceStartup::Failed;

  g_autoptr(GMainLoop) loop = g_main_loop_new(nullptr, FALSE);
  g_autoptr(GCancellable) cancellation = g_cancellable_new();
  ActivationCall call{loop};
  // The timer only cancels. The async completion must run before stack-owned callback state
  // is released, including a timeout while acquiring the session bus.
  const auto bus_budget = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
  if (bus_budget <= 0) {
    bootstrap.Report(anywork::InstanceEvent::Unavailable);
    return anywork::InstanceStartup::Failed;
  }
  const guint watchdog = g_timeout_add(static_cast<guint>(bus_budget), cancel_call, cancellation);
  g_bus_get(G_BUS_TYPE_SESSION, cancellation, bus_ready, &call);
  g_main_loop_run(loop);
  g_autoptr(GDBusConnection) connection = call.connection;

  const std::string application_id = InstanceApplicationId(bootstrap.key());
  std::string object_path = "/" + application_id;
  std::replace(object_path.begin(), object_path.end(), '.', '/');
  while (connection != nullptr && Clock::now() < deadline && !g_cancellable_is_cancelled(cancellation)) {
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
    if (remaining <= 0) break;
    GVariantBuilder platform_data;
    g_variant_builder_init(&platform_data, G_VARIANT_TYPE_VARDICT);
    // GtkApplication 3 reads desktop-startup-id on both X11 and Wayland.
    // GDK forwards a Wayland activation token from that field to the compositor.
    const gchar* startup_id = g_getenv("XDG_ACTIVATION_TOKEN");
    if (startup_id == nullptr) startup_id = g_getenv("DESKTOP_STARTUP_ID");
    if (startup_id != nullptr) {
      g_variant_builder_add(&platform_data, "{sv}", "desktop-startup-id", g_variant_new_string(startup_id));
    }
    // GApplication's standard Activate interface, with an actual reply and a single deadline.
    // NO_AUTO_START prevents D-Bus from launching a service or stealing a not-yet-published name.
    g_dbus_connection_call(connection, application_id.c_str(), object_path.c_str(),
        "org.freedesktop.Application", "Activate", g_variant_new("(a{sv})", &platform_data),
        G_VARIANT_TYPE_UNIT, G_DBUS_CALL_FLAGS_NO_AUTO_START, static_cast<gint>(remaining),
        cancellation, activation_finished, &call);
    g_main_loop_run(loop);
    if (call.accepted) {
      g_source_remove(watchdog);
      bootstrap.Report(anywork::InstanceEvent::Redirected);
      return anywork::InstanceStartup::Redirected;
    }
    claim = bootstrap.Claim();
    if (claim == anywork::InstanceClaim::Primary) {
      g_source_remove(watchdog);
      return anywork::InstanceStartup::Primary;
    }
    if (claim == anywork::InstanceClaim::Failed) break;
    g_usleep(50000);
  }
  g_source_remove(watchdog);
  bootstrap.Report(anywork::InstanceEvent::Unavailable);
  return anywork::InstanceStartup::Failed;
}
