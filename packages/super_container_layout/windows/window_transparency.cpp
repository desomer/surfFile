#include "window_transparency.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

void RegisterWindowTransparency(flutter::BinaryMessenger* messenger,
                                HWND window) {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "super_container_layout/window_transparency",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [window](const auto& call, auto result) {
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
}
