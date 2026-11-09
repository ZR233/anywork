#include "local_file_dialogs.h"

#include <shobjidl.h>
#include <shlobj.h>
#include <shlwapi.h>
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

bool StringArgument(const flutter::EncodableValue* arguments,
                    std::wstring* text) {
  const auto* value = arguments == nullptr
                          ? nullptr
                          : std::get_if<std::string>(arguments);
  if (value == nullptr || value->empty() ||
      value->find('\0') != std::string::npos) return false;
  const int size = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        value->data(),
                                        static_cast<int>(value->size()),
                                        nullptr, 0);
  if (size == 0) return false;
  text->resize(size);
  return ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                               value->data(), static_cast<int>(value->size()),
                               text->data(), size) == size;
}

void Save(HWND window, const std::wstring& filename, Result* result) {
  Microsoft::WRL::ComPtr<IFileSaveDialog> dialog;
  HRESULT status = ::CoCreateInstance(CLSID_FileSaveDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(dialog.GetAddressOf()));
  if (FAILED(status)) return Fail(result, "Create save dialog", status);
  DWORD options = 0;
  status = dialog->GetOptions(&options);
  if (FAILED(status)) return Fail(result, "Read save options", status);
  status = dialog->SetOptions(options | FOS_FORCEFILESYSTEM |
                              FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR |
                              FOS_OVERWRITEPROMPT | FOS_NOTESTFILECREATE);
  if (FAILED(status)) return Fail(result, "Configure save dialog", status);
  status = dialog->SetFileName(::PathFindFileNameW(filename.c_str()));
  if (FAILED(status)) return Fail(result, "Set suggested filename", status);
  status = dialog->Show(window);
  if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    result->Success();
    return;
  }
  if (FAILED(status)) return Fail(result, "Show save dialog", status);
  Microsoft::WRL::ComPtr<IShellItem> item;
  status = dialog->GetResult(item.GetAddressOf());
  if (FAILED(status)) return Fail(result, "Read save selection", status);
  PWSTR path = nullptr;
  status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
  if (FAILED(status)) return Fail(result, "Read save path", status);
  const std::string utf8 = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  if (utf8.empty()) return Fail(result, "Decode save path", E_INVALIDARG);
  result->Success(flutter::EncodableValue(utf8));
}

void Reveal(const std::wstring& path, Result* result) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  if (::PathIsRelativeW(path.c_str()) ||
      attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    return Fail(result, "Find original local file",
                HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND));
  }
  PIDLIST_ABSOLUTE item = nullptr;
  HRESULT status = ::SHParseDisplayName(path.c_str(), nullptr, &item, 0, nullptr);
  if (FAILED(status)) return Fail(result, "Resolve original local file", status);
  status = ::SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
  ::CoTaskMemFree(item);
  if (FAILED(status)) return Fail(result, "Reveal original local file", status);
  result->Success();
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
        if (call.method_name() == "saveFile" ||
            call.method_name() == "revealFile") {
          std::wstring text;
          if (!StringArgument(call.arguments(), &text)) {
            result->Error("invalid_arguments", "Expected a filename or local path.");
            return;
          }
          if (call.method_name() == "saveFile") {
            Save(window, text, result.get());
          } else {
            Reveal(text, result.get());
          }
          return;
        }
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
