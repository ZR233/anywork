#ifndef RUNNER_LOCAL_FILE_DIALOGS_H_
#define RUNNER_LOCAL_FILE_DIALOGS_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

namespace anywork {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLocalFileDialogs(flutter::BinaryMessenger* messenger, HWND window);

}  // namespace anywork

#endif  // RUNNER_LOCAL_FILE_DIALOGS_H_
