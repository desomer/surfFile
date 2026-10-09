#include "external_file_drag.h"

#include <shlobj.h>
#include <shlwapi.h>
#include <windows.h>

#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace {

FORMATETC FileFormat() {
  return {CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
}

class FileDataObject final : public IDataObject {
 public:
  explicit FileDataObject(std::vector<std::wstring> paths)
      : paths_(std::move(paths)) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDataObject) return E_NOINTERFACE;
    *object = static_cast<IDataObject*>(this);
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&references_);
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return count;
  }

  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* format,
                                    STGMEDIUM* medium) override {
    if (!medium) return E_POINTER;
    const HRESULT status = QueryGetData(format);
    if (FAILED(status)) return status;

    size_t bytes = sizeof(DROPFILES) + sizeof(wchar_t);
    for (const auto& path : paths_) {
      bytes += (path.size() + 1) * sizeof(wchar_t);
    }
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!memory) return STG_E_MEDIUMFULL;
    auto* drop = static_cast<DROPFILES*>(GlobalLock(memory));
    if (!drop) {
      GlobalFree(memory);
      return STG_E_MEDIUMFULL;
    }

    drop->pFiles = sizeof(DROPFILES);
    drop->pt = {};
    drop->fNC = FALSE;
    drop->fWide = TRUE;
    auto* output = reinterpret_cast<wchar_t*>(
        reinterpret_cast<BYTE*>(drop) + sizeof(DROPFILES));
    for (const auto& path : paths_) {
      std::memcpy(output, path.c_str(), (path.size() + 1) * sizeof(wchar_t));
      output += path.size() + 1;
    }
    *output = L'\0';
    GlobalUnlock(memory);

    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = memory;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* format) override {
    if (!format) return E_POINTER;
    if (format->cfFormat != CF_HDROP ||
        format->dwAspect != DVASPECT_CONTENT ||
        (format->tymed & TYMED_HGLOBAL) == 0) {
      return DV_E_FORMATETC;
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*,
                                                   FORMATETC* output) override {
    if (!output) return E_POINTER;
    output->ptd = nullptr;
    return DATA_S_SAMEFORMATETC;
  }

  HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction,
                                           IEnumFORMATETC** formats) override {
    if (!formats) return E_POINTER;
    if (direction != DATADIR_GET) return E_NOTIMPL;
    auto format = FileFormat();
    return SHCreateStdEnumFmtEtc(1, &format, formats);
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
  LONG references_ = 1;
  std::vector<std::wstring> paths_;
};

class FileDropSource final : public IDropSource {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (iid != IID_IUnknown && iid != IID_IDropSource) return E_NOINTERFACE;
    *object = static_cast<IDropSource*>(this);
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&references_);
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return count;
  }

  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape_pressed,
                                               DWORD keys) override {
    if (escape_pressed) return DRAGDROP_S_CANCEL;
    if ((keys & MK_LBUTTON) == 0) return DRAGDROP_S_DROP;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override {
    return DRAGDROP_S_USEDEFAULTCURSORS;
  }

 private:
  LONG references_ = 1;
};

bool ToWide(const std::string& value, std::wstring* output) {
  if (value.empty()) return false;
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length == 0) return false;
  output->resize(length);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                             static_cast<int>(value.size()), output->data(),
                             length) == length;
}

}  // namespace

void StartWindowsFileDrag(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* values =
      arguments ? std::get_if<flutter::EncodableList>(arguments) : nullptr;
  if (!values || values->empty()) {
    result->Error("invalid_drag_paths", "No file paths were provided.");
    return;
  }

  std::vector<std::wstring> paths;
  paths.reserve(values->size());
  for (const auto& value : *values) {
    const auto* path = std::get_if<std::string>(&value);
    std::wstring wide_path;
    if (!path || !ToWide(*path, &wide_path)) {
      result->Error("invalid_drag_path", "A file path is invalid UTF-8.");
      return;
    }
    if (GetFileAttributesW(wide_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
      result->Error("drag_path_unavailable",
                    "A file to drag no longer exists (Win32 " +
                        std::to_string(GetLastError()) + ").");
      return;
    }
    paths.push_back(std::move(wide_path));
  }

  auto* data = new FileDataObject(std::move(paths));
  auto* source = new FileDropSource();
  DWORD effect = DROPEFFECT_NONE;
  const HRESULT status = DoDragDrop(data, source, DROPEFFECT_COPY, &effect);
  data->Release();
  source->Release();
  if (FAILED(status)) {
    result->Error("file_drag_failed",
                  "Windows could not start the file drag (HRESULT " +
                      std::to_string(status) + ").");
    return;
  }
  result->Success();
}
