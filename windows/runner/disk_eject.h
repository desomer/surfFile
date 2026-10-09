#ifndef RUNNER_DISK_EJECT_H_
#define RUNNER_DISK_EJECT_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>

#include <memory>

// Posted to the window when an ejection started by StartDiskEject finishes.
constexpr UINT kDiskEjectDoneMessage = WM_APP + 0x51;

// Whether the drive can be ejected: removable media, optical drive, or a fixed
// disk on an external bus (USB, 1394, SD). The system drive never is.
bool IsEjectableDrive(wchar_t letter);

// Ejects the drive named by |arguments| ("E:\\") on a worker thread. |result|
// is completed on the window thread by HandleDiskEjectDone.
void StartDiskEject(
    HWND window, const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

// Completes the ejection posted with kDiskEjectDoneMessage.
void HandleDiskEjectDone(LPARAM lparam);

#endif  // RUNNER_DISK_EJECT_H_
