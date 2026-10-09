#include "flutter_window.h"

#include <optional>
#include <iostream>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>

#include "flutter/generated_plugin_registrant.h"
#include "disk_eject.h"
#include "external_file_drag.h"
#include "window_transparency.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  const HRESULT drop_result = ExternalFileDrop::Register(
      flutter_controller_->view()->GetNativeWindow(),
      flutter_controller_->engine()->messenger(), &external_file_drop_);
  if (FAILED(drop_result)) {
    std::cerr << "Cannot register Windows file drop: " << drop_result << std::endl;
    return false;
  }
  flutter::MethodChannel<flutter::EncodableValue> external_file_drag(
      flutter_controller_->engine()->messenger(), "surf_file/external_drop",
      &flutter::StandardMethodCodec::GetInstance());
  external_file_drag.SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "startDrag") {
          result->NotImplemented();
          return;
        }
        StartWindowsFileDrag(call.arguments(), std::move(result));
      });
  flutter::MethodChannel<flutter::EncodableValue> disk_space(
      flutter_controller_->engine()->messenger(), "surf_file/disk_space",
      &flutter::StandardMethodCodec::GetInstance());
  disk_space.SetMethodCallHandler(
      [window = GetHandle()](const auto& call, auto result) {
        if (call.method_name() == "eject") {
          StartDiskEject(window, call.arguments(), std::move(result));
          return;
        }
        if (call.method_name() != "getDisks") {
          result->NotImplemented();
          return;
        }
        const DWORD drives = GetLogicalDrives();
        if (drives == 0) {
          result->Error("disk_enumeration_failed",
                        "Cannot enumerate drives (Win32 " +
                            std::to_string(GetLastError()) + ").");
          return;
        }
        flutter::EncodableList disks;
        for (int index = 0; index < 26; ++index) {
          if ((drives & (1u << index)) == 0) continue;
          const std::string path =
              std::string(1, static_cast<char>('A' + index)) + ":\\";
          const std::wstring wide_path(path.begin(), path.end());
          ULARGE_INTEGER available{}, total{}, free{};
          flutter::EncodableMap disk;
          disk[flutter::EncodableValue("path")] = flutter::EncodableValue(path);
          // Avoid Windows showing an insert-media dialog for empty drives.
          DWORD previous_mode = 0;
          SetThreadErrorMode(SEM_FAILCRITICALERRORS, &previous_mode);
          const BOOL success = GetDiskFreeSpaceExW(
              wide_path.c_str(), &available, &total, &free);
          const DWORD error = success ? ERROR_SUCCESS : GetLastError();
          disk[flutter::EncodableValue("ejectable")] = flutter::EncodableValue(
              IsEjectableDrive(static_cast<wchar_t>('A' + index)));
          SetThreadErrorMode(previous_mode, nullptr);
          if (!success || total.QuadPart == 0) {
            disk[flutter::EncodableValue("error")] = flutter::EncodableValue(
                "Capacity unavailable (Win32 " + std::to_string(error) + ").");
          } else {
            disk[flutter::EncodableValue("totalBytes")] =
                flutter::EncodableValue(static_cast<int64_t>(total.QuadPart));
            disk[flutter::EncodableValue("freeBytes")] =
                flutter::EncodableValue(static_cast<int64_t>(free.QuadPart));
          }
          disks.emplace_back(disk);
        }
        result->Success(flutter::EncodableValue(disks));
      });
  RegisterWindowTransparency(flutter_controller_->engine()->messenger(),
                             GetHandle());
  shell_context_menu_ = std::make_unique<ShellContextMenu>(GetHandle());
  flutter::MethodChannel<flutter::EncodableValue> context_menu_channel(
      flutter_controller_->engine()->messenger(), "surf_file/context_menu",
      &flutter::StandardMethodCodec::GetInstance());
  context_menu_channel.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        shell_context_menu_->HandleCall(call, std::move(result));
      });
  flutter::MethodChannel<flutter::EncodableValue> personal_folders(
      flutter_controller_->engine()->messenger(),
      "surf_file/personal_folders",
      &flutter::StandardMethodCodec::GetInstance());
  personal_folders.SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "getPersonalFolders") {
          result->NotImplemented();
          return;
        }

        const std::pair<const char*, const KNOWNFOLDERID*> folders[] = {
            {"Desktop", &FOLDERID_Desktop},
            {"Documents", &FOLDERID_Documents},
            {"Downloads", &FOLDERID_Downloads},
            {"Pictures", &FOLDERID_Pictures},
            {"Music", &FOLDERID_Music},
            {"Videos", &FOLDERID_Videos},
        };
        flutter::EncodableMap paths;
        for (const auto& folder : folders) {
          PWSTR path = nullptr;
          const HRESULT status =
              SHGetKnownFolderPath(*folder.second, 0, nullptr, &path);
          if (FAILED(status)) {
            CoTaskMemFree(path);
            result->Error(
                "personal_folder_unavailable",
                std::string("Cannot resolve ") + folder.first +
                    " (HRESULT " + std::to_string(status) + ")");
            return;
          }

          const int length = static_cast<int>(wcslen(path));
          const int size = WideCharToMultiByte(
              CP_UTF8, WC_ERR_INVALID_CHARS, path, length, nullptr, 0, nullptr,
              nullptr);
          if (size == 0) {
            CoTaskMemFree(path);
            result->Error("personal_folder_encoding",
                          std::string("Cannot encode ") + folder.first);
            return;
          }
          std::string utf8_path(size, '\0');
          const int converted = WideCharToMultiByte(
              CP_UTF8, WC_ERR_INVALID_CHARS, path, length, utf8_path.data(), size,
              nullptr, nullptr);
          CoTaskMemFree(path);
          if (converted != size) {
            result->Error("personal_folder_encoding",
                          std::string("Cannot encode ") + folder.first);
            return;
          }
          paths[flutter::EncodableValue(folder.first)] =
              flutter::EncodableValue(utf8_path);
        }
        result->Success(flutter::EncodableValue(paths));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (external_file_drop_) {
    external_file_drop_->Revoke();
    external_file_drop_->Release();
    external_file_drop_ = nullptr;
  }
  shell_context_menu_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kDiskEjectDoneMessage) {
    HandleDiskEjectDone(lparam);
    return 0;
  }
  if (shell_context_menu_) {
    const auto result = shell_context_menu_->HandleMessage(message, wparam, lparam);
    if (result) return *result;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
