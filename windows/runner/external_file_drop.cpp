#include "external_file_drop.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <string>
#include <vector>

namespace {
FORMATETC FileFormat() {
  return {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
}
}

ExternalFileDrop::ExternalFileDrop(HWND window,
                                 flutter::BinaryMessenger* messenger)
    : window_(window),
      channel_(messenger, "surf_file/external_drop",
               &flutter::StandardMethodCodec::GetInstance()) {}

HRESULT ExternalFileDrop::Register(HWND window,
                                  flutter::BinaryMessenger* messenger,
                                  ExternalFileDrop** target) {
  auto* drop = new ExternalFileDrop(window, messenger);
  const HRESULT result = RegisterDragDrop(window, drop);
  if (FAILED(result)) {
    drop->Release();
    return result;
  }
  *target = drop;
  return S_OK;
}

void ExternalFileDrop::Revoke() {
  RevokeDragDrop(window_);
}

HRESULT STDMETHODCALLTYPE ExternalFileDrop::QueryInterface(REFIID iid,
                                                           void** object) {
  if (!object) return E_POINTER;
  *object = nullptr;
  if (iid != IID_IUnknown && iid != IID_IDropTarget) return E_NOINTERFACE;
  *object = static_cast<IDropTarget*>(this);
  AddRef();
  return S_OK;
}

ULONG STDMETHODCALLTYPE ExternalFileDrop::AddRef() {
  return InterlockedIncrement(&references_);
}

ULONG STDMETHODCALLTYPE ExternalFileDrop::Release() {
  const LONG count = InterlockedDecrement(&references_);
  if (count == 0) delete this;
  return count;
}

void ExternalFileDrop::Send(const char* event, POINTL point) {
  POINT client = {point.x, point.y};
  ScreenToClient(window_, &client);
  channel_.InvokeMethod(event, std::make_unique<flutter::EncodableValue>(
      flutter::EncodableList{flutter::EncodableValue(double(client.x)),
                             flutter::EncodableValue(double(client.y))}));
}

void ExternalFileDrop::SetEffect(DWORD* effect) {
  // Le choix final appartient au dialogue Dart ; la source ne doit rien effacer.
  *effect = accepts_files_ && (*effect & DROPEFFECT_COPY)
                ? DROPEFFECT_COPY : DROPEFFECT_NONE;
}

HRESULT STDMETHODCALLTYPE ExternalFileDrop::DragEnter(IDataObject* data,
    DWORD, POINTL point, DWORD* effect) {
  auto format = FileFormat();
  accepts_files_ = data && data->QueryGetData(&format) == S_OK;
  SetEffect(effect);
  if (accepts_files_) Send("entered", point);
  return S_OK;
}

HRESULT STDMETHODCALLTYPE ExternalFileDrop::DragOver(DWORD, POINTL point,
                                                      DWORD* effect) {
  SetEffect(effect);
  if (accepts_files_) Send("updated", point);
  return S_OK;
}

HRESULT STDMETHODCALLTYPE ExternalFileDrop::DragLeave() {
  accepts_files_ = false;
  channel_.InvokeMethod("exited", nullptr);
  return S_OK;
}

HRESULT STDMETHODCALLTYPE ExternalFileDrop::Drop(IDataObject* data, DWORD,
                                                  POINTL point, DWORD* effect) {
  SetEffect(effect);
  if (*effect == DROPEFFECT_NONE) {
    DragLeave();
    return S_OK;
  }
  auto format = FileFormat();
  STGMEDIUM medium{};
  const HRESULT result = data->GetData(&format, &medium);
  if (FAILED(result)) {
    *effect = DROPEFFECT_NONE;
    DragLeave();
    channel_.InvokeMethod("error", std::make_unique<flutter::EncodableValue>(
        "Impossible de lire les fichiers deposes (HRESULT " +
        std::to_string(result) + ")."));
    return result;
  }
  const auto drop = static_cast<HDROP>(medium.hGlobal);
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  flutter::EncodableList paths;
  bool valid = count > 0;
  for (UINT index = 0; index < count && valid; ++index) {
    const UINT length = DragQueryFileW(drop, index, nullptr, 0);
    std::vector<wchar_t> wide(length + 1);
    if (length == 0 ||
        DragQueryFileW(drop, index, wide.data(), length + 1) != length) {
      valid = false;
      break;
    }
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        wide.data(), static_cast<int>(length), nullptr, 0, nullptr, nullptr);
    if (size == 0) {
      valid = false;
      break;
    }
    std::string path(size, '\0');
    valid = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        wide.data(), static_cast<int>(length), path.data(), size, nullptr,
        nullptr) == size;
    if (valid) paths.emplace_back(path);
  }
  ReleaseStgMedium(&medium);
  accepts_files_ = false;
  if (!valid) {
    *effect = DROPEFFECT_NONE;
    channel_.InvokeMethod("exited", nullptr);
    channel_.InvokeMethod("error", std::make_unique<flutter::EncodableValue>(
        "Le depot ne fournit pas de chemins de fichiers locaux valides."));
    return S_OK;
  }
  POINT client = {point.x, point.y};
  ScreenToClient(window_, &client);
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("paths")] = flutter::EncodableValue(paths);
  payload[flutter::EncodableValue("x")] = flutter::EncodableValue(double(client.x));
  payload[flutter::EncodableValue("y")] = flutter::EncodableValue(double(client.y));
  channel_.InvokeMethod("drop",
                       std::make_unique<flutter::EncodableValue>(payload));
  return S_OK;
}
