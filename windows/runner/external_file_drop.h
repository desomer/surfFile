#ifndef RUNNER_EXTERNAL_FILE_DROP_H_
#define RUNNER_EXTERNAL_FILE_DROP_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <oleidl.h>

#include <memory>

class ExternalFileDrop final : public IDropTarget {
 public:
  static HRESULT Register(HWND window, flutter::BinaryMessenger* messenger,
                          ExternalFileDrop** target);
  void Revoke();

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;
  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD keys, POINTL point,
                                       DWORD* effect) override;
  HRESULT STDMETHODCALLTYPE DragOver(DWORD keys, POINTL point,
                                      DWORD* effect) override;
  HRESULT STDMETHODCALLTYPE DragLeave() override;
  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD keys, POINTL point,
                                  DWORD* effect) override;

 private:
  ExternalFileDrop(HWND window, flutter::BinaryMessenger* messenger);
  void Send(const char* event, POINTL point);
  void SetEffect(DWORD* effect);

  LONG references_ = 1;
  HWND window_;
  bool accepts_files_ = false;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

#endif  // RUNNER_EXTERNAL_FILE_DROP_H_
