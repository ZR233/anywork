#ifndef RUNNER_DESKTOP_INSTANCE_H_
#define RUNNER_DESKTOP_INSTANCE_H_

#include <string>
#include "studio_instance.h"

std::string InstanceApplicationId(const std::string& key);
anywork::InstanceStartup PrepareDesktopInstance(anywork::DesktopInstanceBootstrap& bootstrap);

#endif
