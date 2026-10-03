#ifndef RUNNER_SHELL_CONTEXT_MENU_H_
#define RUNNER_SHELL_CONTEXT_MENU_H_

#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <map>
#include <optional>
#include <set>

class ShellContextMenu {
 public:
  explicit ShellContextMenu(HWND window);
  ~ShellContextMenu();

  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  void Clear();
  HRESULT Open(const std::wstring& path);
  HRESULT ReadMenu(HMENU menu, flutter::EncodableList* items);
  flutter::EncodableMap Command(UINT id, const std::string& label);
  HRESULT Invoke(UINT id);

  HWND window_;
  POINT position_{};
  HMENU menu_ = nullptr;
  int64_t session_ = 0;
  Microsoft::WRL::ComPtr<IContextMenu> context_;
  Microsoft::WRL::ComPtr<IContextMenu2> context2_;
  Microsoft::WRL::ComPtr<IContextMenu3> context3_;
  std::map<int32_t, HMENU> submenus_;
  std::set<UINT> commands_;
  bool forwarding_ = false;
  std::wstring path_;
};

#endif
