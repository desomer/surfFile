#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>

#include "flutter/generated_plugin_registrant.h"

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
  flutter::MethodChannel<flutter::EncodableValue> transparency_channel(
      flutter_controller_->engine()->messenger(),
      "surf_file/window_transparency",
      &flutter::StandardMethodCodec::GetInstance());
  transparency_channel.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setOpacity") {
          result->NotImplemented();
          return;
        }
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        const auto it = args
            ? args->find(flutter::EncodableValue("opacity"))
            : flutter::EncodableMap::const_iterator{};
        const auto* opacity = args && it != args->end()
            ? std::get_if<double>(&it->second) : nullptr;
        if (!opacity || !(*opacity >= 0.2 && *opacity <= 1.0)) {
          result->Error("invalid_opacity", "Window opacity must be between 0.2 and 1.");
          return;
        }
        const HWND window = GetHandle();
        const LONG_PTR style = GetWindowLongPtr(window, GWL_EXSTYLE);
        const LONG_PTR updated = *opacity < 1.0
            ? style | WS_EX_LAYERED : style & ~WS_EX_LAYERED;
        SetLastError(0);
        if (updated != style &&
            SetWindowLongPtr(window, GWL_EXSTYLE, updated) == 0 &&
            GetLastError() != 0) {
          result->Error("window_opacity_error", "Cannot update window style.");
          return;
        }
        if (*opacity < 1.0 &&
            !SetLayeredWindowAttributes(window, 0,
                static_cast<BYTE>(*opacity * 255.0 + 0.5), LWA_ALPHA)) {
          result->Error("window_opacity_error", "Cannot set window opacity.");
          return;
        }
        RedrawWindow(window, nullptr, nullptr,
                     RDW_INVALIDATE | RDW_FRAME | RDW_ALLCHILDREN);
        result->Success();
      });
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
