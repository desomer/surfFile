#include "shell_context_menu.h"

#include <flutter/standard_method_codec.h>

#include <string>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
constexpr UINT kFirstCommand = 1;
constexpr UINT kLastCommand = 0x7FFF;

const Value* Find(const Map& map, const char* key) {
  const auto it = map.find(Value(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<int64_t> Integer(const Value* value) {
  if (!value) return std::nullopt;
  if (const auto* number = std::get_if<int32_t>(value)) return *number;
  if (const auto* number = std::get_if<int64_t>(value)) return *number;
  return std::nullopt;
}

std::string Utf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int length = static_cast<int>(text.size());
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), length,
                                      nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), length, result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::wstring Utf16(const std::string& text) {
  const int length = static_cast<int>(text.size());
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                      text.data(), length, nullptr, 0);
  if (size == 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), length,
                      result.data(), size);
  return result;
}

std::string MenuLabel(const std::wstring& text) {
  std::wstring label;
  for (size_t i = 0; i < text.size() && text[i] != L'\t'; ++i) {
    if (text[i] == L'&') {
      if (i + 1 < text.size() && text[i + 1] == L'&') {
        label += L'&';
        ++i;
      }
    } else {
      label += text[i];
    }
  }
  return Utf8(label);
}
}  // namespace

ShellContextMenu::ShellContextMenu(HWND window) : window_(window) {}

ShellContextMenu::~ShellContextMenu() { Clear(); }

void ShellContextMenu::Clear() {
  forwarding_ = false;
  if (menu_) DestroyMenu(menu_);
  menu_ = nullptr;
  submenus_.clear();
  commands_.clear();
  path_.clear();
  context3_.Reset();
  context2_.Reset();
  context_.Reset();
}

HRESULT ShellContextMenu::Open(const std::wstring& path) {
  Clear();
  ++session_;
  path_ = path;
  if (!GetCursorPos(&position_)) return HRESULT_FROM_WIN32(GetLastError());

  PIDLIST_ABSOLUTE pidl = nullptr;
  HRESULT status = SHParseDisplayName(path.c_str(), nullptr, &pidl, 0, nullptr);
  if (FAILED(status)) return status;
  Microsoft::WRL::ComPtr<IShellFolder> parent;
  PCUITEMID_CHILD child = nullptr;
  status = SHBindToParent(pidl, IID_PPV_ARGS(parent.GetAddressOf()), &child);
  if (SUCCEEDED(status)) {
    status = parent->GetUIObjectOf(window_, 1, &child, IID_IContextMenu,
                                   nullptr,
                                   reinterpret_cast<void**>(context_.GetAddressOf()));
  }
  CoTaskMemFree(pidl);
  if (FAILED(status)) return status;

  context_.As(&context2_);
  context_.As(&context3_);
  menu_ = CreatePopupMenu();
  if (!menu_) return HRESULT_FROM_WIN32(GetLastError());
  status = context_->QueryContextMenu(menu_, 0, kFirstCommand, kLastCommand,
                                      CMF_NORMAL | CMF_CANRENAME);
  if (FAILED(status)) return status;
  submenus_[0] = menu_;
  return S_OK;
}

Map ShellContextMenu::Command(UINT id, const std::string& label) {
  wchar_t verb[256] = {};
  const HRESULT status = id >= kFirstCommand && id <= kLastCommand
      ? context_->GetCommandString(
          id - kFirstCommand, GCS_VERBW, nullptr,
          reinterpret_cast<LPSTR>(verb), static_cast<UINT>(std::size(verb)))
      : E_INVALIDARG;
  return {
      {Value("id"), Value(static_cast<int32_t>(id))},
      {Value("label"), Value(label)},
      {Value("verb"), Value(SUCCEEDED(status) ? Utf8(verb) : "")},
  };
}

HRESULT ShellContextMenu::ReadMenu(HMENU menu, flutter::EncodableList* items) {
  const int count = GetMenuItemCount(menu);
  if (count < 0) return HRESULT_FROM_WIN32(GetLastError());
  for (int index = 0; index < count; ++index) {
    MENUITEMINFOW info{};
    info.cbSize = sizeof(info);
    info.fMask = MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_STRING;
    if (!GetMenuItemInfoW(menu, index, TRUE, &info))
      return HRESULT_FROM_WIN32(GetLastError());
    std::vector<wchar_t> text(static_cast<size_t>(info.cch) + 1);
    info.dwTypeData = text.data();
    info.cch = static_cast<UINT>(text.size());
    if (!GetMenuItemInfoW(menu, index, TRUE, &info))
      return HRESULT_FROM_WIN32(GetLastError());

    Map item = Command(info.wID, MenuLabel(text.data()));
    item[Value("separator")] = Value((info.fType & MFT_SEPARATOR) != 0);
    item[Value("enabled")] = Value((info.fState & MFS_DISABLED) == 0);
    item[Value("checked")] = Value((info.fState & MFS_CHECKED) != 0);
    item[Value("default")] = Value((info.fState & MFS_DEFAULT) != 0);
    // Owner-drawn extensions must be rendered by Windows, not approximated.
    item[Value("nativeOnly")] = Value((info.fType & MFT_OWNERDRAW) != 0);
    if (info.hSubMenu) {
      int32_t submenu_id = -1;
      for (const auto& submenu : submenus_) {
        if (submenu.second == info.hSubMenu) submenu_id = submenu.first;
      }
      if (submenu_id == -1) {
        submenu_id = static_cast<int32_t>(submenus_.size());
        submenus_[submenu_id] = info.hSubMenu;
      }
      item[Value("submenu")] = Value(submenu_id);
    } else if (!(info.fType & MFT_SEPARATOR) &&
               !(info.fState & MFS_DISABLED) &&
               info.wID >= kFirstCommand && info.wID <= kLastCommand) {
      commands_.insert(info.wID);
    }
    items->emplace_back(item);
  }
  return S_OK;
}

HRESULT ShellContextMenu::Invoke(UINT id) {
  CMINVOKECOMMANDINFOEX info{};
  info.cbSize = sizeof(info);
  info.fMask = CMIC_MASK_UNICODE | CMIC_MASK_PTINVOKE;
  info.hwnd = window_;
  info.lpVerb = MAKEINTRESOURCEA(id - kFirstCommand);
  info.lpVerbW = MAKEINTRESOURCEW(id - kFirstCommand);
  info.nShow = SW_SHOWNORMAL;
  info.ptInvoke = position_;
  return context_->InvokeCommand(reinterpret_cast<LPCMINVOKECOMMANDINFO>(&info));
}

std::optional<LRESULT> ShellContextMenu::HandleMessage(
    UINT message, WPARAM wparam, LPARAM lparam) {
  if (!forwarding_ || (message != WM_INITMENUPOPUP &&
                      message != WM_DRAWITEM && message != WM_MEASUREITEM &&
                      message != WM_MENUCHAR))
    return std::nullopt;
  LRESULT result = 0;
  if (context3_ &&
      SUCCEEDED(context3_->HandleMenuMsg2(message, wparam, lparam, &result)))
    return result;
  if (context2_ &&
      SUCCEEDED(context2_->HandleMenuMsg(message, wparam, lparam)))
    return 0;
  return std::nullopt;
}

void ShellContextMenu::HandleCall(
    const flutter::MethodCall<Value>& call,
    std::unique_ptr<flutter::MethodResult<Value>> result) {
  const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
  if (!args) {
    result->Error("invalid_arguments", "Expected menu arguments.");
    return;
  }
  HRESULT status = S_OK;
  if (call.method_name() == "open") {
    const auto* value = Find(*args, "path");
    const auto* path = value ? std::get_if<std::string>(value) : nullptr;
    if (!path || path->empty() || path->find('\0') != std::string::npos) {
      result->Error("invalid_path", "Expected a file or folder path.");
      return;
    }
    const auto wide_path = Utf16(*path);
    if (wide_path.empty()) {
      result->Error("invalid_path", "Path is not valid UTF-8.");
      return;
    }
    status = Open(wide_path);
    flutter::EncodableList items;
    if (SUCCEEDED(status)) status = ReadMenu(menu_, &items);
    if (SUCCEEDED(status)) {
      result->Success(Value(Map{
          {Value("session"), Value(session_)},
          {Value("items"), Value(items)},
      }));
      return;
    }
    Clear();
  } else {
    const auto session = Integer(Find(*args, "session"));
    if (!session || *session != session_ || !context_) {
      result->Error("expired_menu", "This context menu is no longer available.");
      return;
    }
    if (call.method_name() == "close") {
      Clear();
      result->Success();
      return;
    }
    if (call.method_name() == "submenu") {
      const auto id = Integer(Find(*args, "submenu"));
      if (!id || *id < 0 || *id > INT32_MAX ||
          submenus_.find(static_cast<int32_t>(*id)) == submenus_.end()) {
        result->Error("invalid_submenu", "Unknown submenu.");
        return;
      }
      HMENU submenu = submenus_.at(static_cast<int32_t>(*id));
      int position = 0;
      for (const auto& parent : submenus_) {
        for (int index = 0; index < GetMenuItemCount(parent.second); ++index) {
          if (GetSubMenu(parent.second, index) == submenu) position = index;
        }
      }
      forwarding_ = true;
      HandleMessage(WM_INITMENUPOPUP, reinterpret_cast<WPARAM>(submenu),
                    MAKELPARAM(position, FALSE));
      forwarding_ = false;
      flutter::EncodableList items;
      status = ReadMenu(submenu, &items);
      if (SUCCEEDED(status)) {
        result->Success(Value(items));
        return;
      }
    } else if (call.method_name() == "native") {
      SetForegroundWindow(window_);
      forwarding_ = true;
      const UINT id = TrackPopupMenuEx(
          menu_, TPM_RETURNCMD | TPM_RIGHTBUTTON,
          position_.x, position_.y, window_, nullptr);
      forwarding_ = false;
      PostMessage(window_, WM_NULL, 0, 0);
      if (id == 0) {
        result->Success();
      } else {
        commands_.insert(id);
        result->Success(Value(Command(id, "")));
      }
      return;
    } else if (call.method_name() == "invoke" || call.method_name() == "rename") {
      const auto id = Integer(Find(*args, "id"));
      if (!id || *id < kFirstCommand || *id > kLastCommand ||
          commands_.count(static_cast<UINT>(*id)) == 0) {
        result->Error("invalid_command", "Unknown or disabled command.");
        return;
      }
      if (call.method_name() == "rename") {
        const auto command = Command(static_cast<UINT>(*id), "");
        const auto* verb = std::get_if<std::string>(Find(command, "verb"));
        const auto* name_value = Find(*args, "name");
        const auto* name = name_value
            ? std::get_if<std::string>(name_value) : nullptr;
        if (!verb || *verb != "rename" || !name || name->empty()) {
          result->Error("invalid_rename", "Expected a rename command and name.");
          return;
        }
        const auto wide_name = Utf16(*name);
        if (wide_name.empty() || wide_name == L"." || wide_name == L".." ||
            wide_name.find_first_of(L"<>:\"/\\|?*") != std::wstring::npos ||
            wide_name.back() == L'.' || wide_name.back() == L' ') {
          result->Error("invalid_rename", "Invalid file or folder name.");
          return;
        }
        for (const wchar_t character : wide_name) {
          if (character < 32) {
            result->Error("invalid_rename", "Invalid file or folder name.");
            return;
          }
        }
        const auto parent_end = path_.find_last_of(L"\\/");
        if (parent_end == std::wstring::npos) {
          result->Error("invalid_rename", "Cannot rename this Shell item.");
          return;
        }
        const auto destination = path_.substr(0, parent_end + 1) + wide_name;
        // MoveFileW never replaces an existing destination.
        status = MoveFileW(path_.c_str(), destination.c_str())
            ? S_OK : HRESULT_FROM_WIN32(GetLastError());
      } else {
        status = Invoke(static_cast<UINT>(*id));
      }
      if (SUCCEEDED(status)) {
        result->Success();
        return;
      }
    } else {
      result->NotImplemented();
      return;
    }
  }
  result->Error("shell_menu_error",
                "Windows context menu failed (HRESULT " +
                    std::to_string(status) + ").");
}
