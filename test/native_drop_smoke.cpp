#include "../windows/runner/external_file_drop.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>

#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

class RecordingMessenger final : public flutter::BinaryMessenger {
 public:
  void Send(const std::string& channel, const uint8_t* message, size_t size,
            flutter::BinaryReply = nullptr) const override {
    assert(channel == "surf_file/external_drop");
    const auto call = flutter::StandardMethodCodec::GetInstance()
                          .DecodeMethodCall(message, size);
    assert(call);
    events.push_back(call->method_name());
    if (call->arguments()) arguments = *call->arguments();
  }
  void SetMessageHandler(const std::string&,
                         flutter::BinaryMessageHandler) override {}

  mutable std::vector<std::string> events;
  mutable flutter::EncodableValue arguments;
};

class FileData final : public IDataObject {
 public:
  explicit FileData(std::wstring path) : path_(std::move(path)) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDataObject) return E_NOINTERFACE;
    *object = static_cast<IDataObject*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override { return --references_; }

  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* format) override {
    return format->cfFormat == CF_HDROP && (format->tymed & TYMED_HGLOBAL)
               ? S_OK : DV_E_FORMATETC;
  }
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format,
                                    STGMEDIUM* medium) override {
    if (FAILED(QueryGetData(format))) return DV_E_FORMATETC;
    const size_t size = sizeof(DROPFILES) + (path_.size() + 2) * sizeof(wchar_t);
    const auto memory = GlobalAlloc(GHND, size);
    if (!memory) return E_OUTOFMEMORY;
    auto* data = static_cast<DROPFILES*>(GlobalLock(memory));
    if (!data) {
      GlobalFree(memory);
      return E_OUTOFMEMORY;
    }
    data->pFiles = sizeof(DROPFILES);
    data->fWide = TRUE;
    std::memcpy(reinterpret_cast<char*>(data) + sizeof(DROPFILES),
                path_.data(), path_.size() * sizeof(wchar_t));
    GlobalUnlock(memory);
    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*,
                                                 FORMATETC*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD, IEnumFORMATETC**) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*,
                                   DWORD*) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }
  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

 private:
  ULONG references_ = 1;
  std::wstring path_;
};

int main() {
  assert(SUCCEEDED(OleInitialize(nullptr)));
  const HWND window = CreateWindowW(L"STATIC", L"drop-smoke", WS_OVERLAPPED,
                                    0, 0, 400, 300, nullptr, nullptr,
                                    GetModuleHandleW(nullptr), nullptr);
  assert(window);
  RecordingMessenger messenger;
  ExternalFileDrop* target = nullptr;
  assert(SUCCEEDED(ExternalFileDrop::Register(window, &messenger, &target)));
  POINT origin{0, 0};
  ClientToScreen(window, &origin);
  const POINTL point{origin.x + 40, origin.y + 50};
  const std::wstring path = L"C:\\outside\\" + std::wstring(300, L'a') +
                            L"\\\u00e9chantillon.txt";
  FileData files(path);
  DWORD effect = DROPEFFECT_COPY | DROPEFFECT_MOVE;
  assert(SUCCEEDED(target->DragEnter(&files, 0, point, &effect)));
  assert(effect == DROPEFFECT_COPY);
  assert(messenger.events.back() == "entered");
  effect = DROPEFFECT_COPY | DROPEFFECT_MOVE;
  assert(SUCCEEDED(target->Drop(&files, 0, point, &effect)));
  assert(effect == DROPEFFECT_COPY);
  assert(messenger.events.back() == "drop");
  const auto& payload = std::get<flutter::EncodableMap>(messenger.arguments);
  const auto& paths = std::get<flutter::EncodableList>(
      payload.at(flutter::EncodableValue("paths")));
  assert(paths.size() == 1);
  const auto& received = std::get<std::string>(paths[0]);
  assert(received.size() > MAX_PATH);
  assert(received.find("\xc3\xa9" "chantillon.txt") != std::string::npos);
  assert(std::get<double>(payload.at(flutter::EncodableValue("x"))) == 40);
  assert(std::get<double>(payload.at(flutter::EncodableValue("y"))) == 50);
  effect = DROPEFFECT_MOVE;
  assert(SUCCEEDED(target->DragEnter(&files, 0, point, &effect)));
  assert(effect == DROPEFFECT_NONE);
  assert(SUCCEEDED(target->DragLeave()));
  assert(messenger.events.back() == "exited");
  target->Revoke();
  target->Release();
  DestroyWindow(window);
  OleUninitialize();
  std::cout << "OLE drop smoke passed: paths, Unicode, coordinates, safe effects."
            << std::endl;
  return 0;
}
