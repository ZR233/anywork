#include "local_file_dialogs.h"

#include <shobjidl.h>
#include <wrl/client.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <string>
#include <vector>

#include "utils.h"

namespace anywork {
namespace {

using Result = flutter::MethodResult<flutter::EncodableValue>;

void Fail(Result* result, const char* operation, HRESULT error) {
  result->Error("file_dialog_failed",
                std::string(operation) + " failed: " +
                    std::to_string(static_cast<long>(error)));
}

bool FileFilter(const flutter::EncodableValue* arguments, std::wstring* pattern) {
  const auto* extensions = arguments == nullptr
                               ? nullptr
                               : std::get_if<flutter::EncodableList>(arguments);
  if (extensions == nullptr) return false;
  for (const auto& value : *extensions) {
    const auto* extension = std::get_if<std::string>(&value);
    if (extension == nullptr || extension->empty() ||
        !std::all_of(extension->begin(), extension->end(), [](unsigned char c) {
          return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                 (c >= '0' && c <= '9');
        })) {
      return false;
    }
    if (!pattern->empty()) pattern->append(L";");
    pattern->append(L"*.");
    pattern->append(extension->begin(), extension->end());
  }
  return true;
}

void Pick(HWND window, bool directory, const std::wstring& pattern,
          Result* result) {
  Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
  HRESULT status = ::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(dialog.GetAddressOf()));
  if (FAILED(status)) return Fail(result, "Create file dialog", status);
  DWORD options = 0;
  status = dialog->GetOptions(&options);
  if (FAILED(status)) return Fail(result, "Read file dialog options", status);
  options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR |
             (directory ? FOS_PICKFOLDERS
                        : FOS_FILEMUSTEXIST | FOS_ALLOWMULTISELECT);
  status = dialog->SetOptions(options);
  if (FAILED(status)) return Fail(result, "Configure file dialog", status);
  if (!pattern.empty()) {
    const COMDLG_FILTERSPEC filter = {pattern.c_str(), pattern.c_str()};
    status = dialog->SetFileTypes(1, &filter);
    if (FAILED(status)) return Fail(result, "Set file filter", status);
  }
  status = dialog->Show(window);
  if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    if (directory) {
      result->Success();
    } else {
      result->Success(flutter::EncodableValue(flutter::EncodableList{}));
    }
    return;
  }
  if (FAILED(status)) return Fail(result, "Show file dialog", status);

  Microsoft::WRL::ComPtr<IShellItemArray> items;
  status = dialog->GetResults(items.GetAddressOf());
  if (FAILED(status)) return Fail(result, "Read file selection", status);
  DWORD count = 0;
  status = items->GetCount(&count);
  if (FAILED(status)) return Fail(result, "Count selected files", status);
  if (count == 0) return Fail(result, "Read file selection", E_FAIL);
  flutter::EncodableList paths;
  for (DWORD index = 0; index < count; ++index) {
    Microsoft::WRL::ComPtr<IShellItem> item;
    status = items->GetItemAt(index, item.GetAddressOf());
    if (FAILED(status)) return Fail(result, "Read selected file", status);
    PWSTR path = nullptr;
    status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (FAILED(status)) return Fail(result, "Read selected path", status);
    const std::string utf8 = Utf8FromUtf16(path);
    ::CoTaskMemFree(path);
    if (utf8.empty()) return Fail(result, "Decode selected path", E_INVALIDARG);
    paths.emplace_back(utf8);
  }
  if (directory) {
    if (paths.size() != 1) return Fail(result, "Read selected directory", E_FAIL);
    result->Success(paths.front());
  } else {
    result->Success(flutter::EncodableValue(std::move(paths)));
  }
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLocalFileDialogs(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "io.github.zr233.anywork/file_dialogs",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<Result> result) {
        const bool directory = call.method_name() == "pickDirectory";
        if (!directory && call.method_name() != "pickFiles") {
          result->NotImplemented();
          return;
        }
        std::wstring pattern;
        if (!directory && !FileFilter(call.arguments(), &pattern)) {
          result->Error("invalid_arguments", "Expected file extensions.");
          return;
        }
        Pick(window, directory, pattern, result.get());
      });
  return channel;
}

}  // namespace anywork
