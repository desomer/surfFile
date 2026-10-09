#include "disk_eject.h"

// initguid.h makes winioctl.h define GUID_DEVINTERFACE_DISK and _CDROM here.
#include <initguid.h>
#include <winioctl.h>
#include <cfgmgr32.h>
#include <setupapi.h>

#include <cctype>
#include <cwctype>
#include <string>
#include <thread>
#include <vector>

namespace {

using Result = flutter::MethodResult<flutter::EncodableValue>;

struct EjectOutcome {
  // Empty on success, otherwise "in_use" or "failed".
  std::string code;
  std::string message;
};

struct EjectJob {
  std::unique_ptr<Result> result;
  EjectOutcome outcome;
};

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string utf8(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      utf8.data(), size, nullptr, nullptr);
  return utf8;
}

std::string Win32Error(const char* what, DWORD error) {
  return std::string(what) + " (Win32 " + std::to_string(error) + ").";
}

// Suppresses Windows' "insert a disk" dialog while in scope.
class QuietErrors {
 public:
  QuietErrors() { SetThreadErrorMode(SEM_FAILCRITICALERRORS, &previous_); }
  ~QuietErrors() { SetThreadErrorMode(previous_, nullptr); }

 private:
  DWORD previous_ = 0;
};

HANDLE OpenVolume(wchar_t letter, DWORD access) {
  wchar_t path[] = L"\\\\.\\X:";
  path[4] = letter;
  return CreateFileW(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                     OPEN_EXISTING, 0, nullptr);
}

bool GetDeviceNumber(HANDLE device, STORAGE_DEVICE_NUMBER* number) {
  DWORD bytes = 0;
  return DeviceIoControl(device, IOCTL_STORAGE_GET_DEVICE_NUMBER, nullptr, 0,
                         number, sizeof(*number), &bytes, nullptr) != FALSE;
}

bool IsSystemDrive(wchar_t letter) {
  wchar_t windows[MAX_PATH]{};
  return GetSystemWindowsDirectoryW(windows, MAX_PATH) > 0 &&
         std::towupper(windows[0]) == std::towupper(letter);
}

// External disks are usually reported as DRIVE_FIXED: their bus tells them
// apart from internal disks.
bool IsOnExternalBus(wchar_t letter) {
  const HANDLE volume = OpenVolume(letter, 0);
  if (volume == INVALID_HANDLE_VALUE) return false;
  STORAGE_PROPERTY_QUERY query{};
  query.PropertyId = StorageDeviceProperty;
  query.QueryType = PropertyStandardQuery;
  BYTE buffer[1024]{};
  DWORD bytes = 0;
  const BOOL success =
      DeviceIoControl(volume, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                      sizeof(query), buffer, sizeof(buffer), &bytes, nullptr);
  CloseHandle(volume);
  if (!success || bytes < sizeof(STORAGE_DEVICE_DESCRIPTOR)) return false;
  const auto* descriptor =
      reinterpret_cast<const STORAGE_DEVICE_DESCRIPTOR*>(buffer);
  switch (descriptor->BusType) {
    case BusTypeUsb:
    case BusType1394:
    case BusTypeSd:
    case BusTypeMmc:
      return true;
    default:
      return descriptor->RemovableMedia != FALSE;
  }
}

// Disk (or optical drive) device node holding the volume.
DEVINST FindDiskDevice(const STORAGE_DEVICE_NUMBER& target) {
  const GUID& guid = target.DeviceType == FILE_DEVICE_CD_ROM
                         ? GUID_DEVINTERFACE_CDROM
                         : GUID_DEVINTERFACE_DISK;
  const HDEVINFO set = SetupDiGetClassDevsW(
      &guid, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (set == INVALID_HANDLE_VALUE) return 0;
  DEVINST found = 0;
  SP_DEVICE_INTERFACE_DATA interface_data{};
  interface_data.cbSize = sizeof(interface_data);
  for (DWORD index = 0;
       found == 0 &&
       SetupDiEnumDeviceInterfaces(set, nullptr, &guid, index, &interface_data);
       ++index) {
    DWORD size = 0;
    SetupDiGetDeviceInterfaceDetailW(set, &interface_data, nullptr, 0, &size,
                                     nullptr);
    if (size == 0) continue;
    std::vector<BYTE> buffer(size);
    auto* detail =
        reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buffer.data());
    detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
    SP_DEVINFO_DATA info{};
    info.cbSize = sizeof(info);
    if (!SetupDiGetDeviceInterfaceDetailW(set, &interface_data, detail, size,
                                          nullptr, &info)) {
      continue;
    }
    const HANDLE device =
        CreateFileW(detail->DevicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    nullptr, OPEN_EXISTING, 0, nullptr);
    if (device == INVALID_HANDLE_VALUE) continue;
    STORAGE_DEVICE_NUMBER number{};
    if (GetDeviceNumber(device, &number) &&
        number.DeviceType == target.DeviceType &&
        number.DeviceNumber == target.DeviceNumber) {
      found = info.DevInst;
    }
    CloseHandle(device);
  }
  SetupDiDestroyDeviceInfoList(set);
  return found;
}

// First device from |device| up to the root that PnP can eject (for a USB
// disk, its USBSTOR or UASP device), or 0.
DEVINST FindRemovableAncestor(DEVINST device) {
  for (int depth = 0; device != 0 && depth < 8; ++depth) {
    ULONG capabilities = 0;
    ULONG size = sizeof(capabilities);
    if (CM_Get_DevNode_Registry_PropertyW(device, CM_DRP_CAPABILITIES, nullptr,
                                          &capabilities, &size,
                                          0) == CR_SUCCESS &&
        (capabilities & CM_DEVCAP_REMOVABLE) != 0) {
      return device;
    }
    DEVINST parent = 0;
    if (CM_Get_Parent(&parent, device, 0) != CR_SUCCESS) return 0;
    device = parent;
  }
  return 0;
}

// Safe removal, as the notification area does. Retries because the shell and
// antivirus software often hold the volume briefly after its last use.
EjectOutcome RequestDeviceEject(DEVINST device) {
  PNP_VETO_TYPE veto = PNP_VetoTypeUnknown;
  std::wstring vetoer;
  CONFIGRET status = CR_SUCCESS;
  for (int attempt = 0; attempt < 3; ++attempt) {
    if (attempt > 0) Sleep(500);
    wchar_t name[MAX_PATH]{};
    veto = PNP_VetoTypeUnknown;
    status = CM_Request_Device_EjectW(device, &veto, name, MAX_PATH, 0);
    if (status == CR_SUCCESS && veto == PNP_VetoTypeUnknown) return {};
    vetoer = name;
  }
  if (veto == PNP_VetoTypeUnknown) {
    return {"failed",
            "Eject request failed (CONFIGRET " + std::to_string(status) + ")."};
  }
  const bool in_use = veto == PNP_VetoOutstandingOpen ||
                      veto == PNP_VetoDevice || veto == PNP_VetoDriver ||
                      veto == PNP_VetoPendingClose ||
                      veto == PNP_VetoWindowsApp ||
                      veto == PNP_VetoWindowsService;
  return {in_use ? "in_use" : "failed",
          "Eject vetoed (type " + std::to_string(veto) + ")" +
              (vetoer.empty() ? "" : " by " + ToUtf8(vetoer)) + "."};
}

// Media ejection (optical tray, card in a built-in reader).
EjectOutcome EjectMedia(wchar_t letter) {
  HANDLE volume = OpenVolume(letter, GENERIC_READ | GENERIC_WRITE);
  if (volume == INVALID_HANDLE_VALUE) volume = OpenVolume(letter, GENERIC_READ);
  if (volume == INVALID_HANDLE_VALUE) {
    return {"failed", Win32Error("Cannot open the volume", GetLastError())};
  }
  DWORD bytes = 0;
  bool locked = false;
  DWORD lock_error = ERROR_SUCCESS;
  for (int attempt = 0; attempt < 10 && !locked; ++attempt) {
    if (attempt > 0) Sleep(100);
    locked = DeviceIoControl(volume, FSCTL_LOCK_VOLUME, nullptr, 0, nullptr, 0,
                             &bytes, nullptr) != FALSE;
    lock_error = locked ? ERROR_SUCCESS : GetLastError();
    // An empty drive cannot be locked but its tray can still open.
    if (lock_error == ERROR_NOT_READY) break;
  }
  if (!locked && lock_error != ERROR_NOT_READY) {
    CloseHandle(volume);
    return {"in_use", Win32Error("Cannot lock the volume", lock_error)};
  }
  if (locked) {
    DeviceIoControl(volume, FSCTL_DISMOUNT_VOLUME, nullptr, 0, nullptr, 0,
                    &bytes, nullptr);
  }
  PREVENT_MEDIA_REMOVAL allow{};
  allow.PreventMediaRemoval = FALSE;
  DeviceIoControl(volume, IOCTL_STORAGE_MEDIA_REMOVAL, &allow, sizeof(allow),
                  nullptr, 0, &bytes, nullptr);
  const BOOL ejected = DeviceIoControl(volume, IOCTL_STORAGE_EJECT_MEDIA,
                                       nullptr, 0, nullptr, 0, &bytes, nullptr);
  const DWORD error = ejected ? ERROR_SUCCESS : GetLastError();
  CloseHandle(volume);
  if (!ejected) return {"failed", Win32Error("Cannot eject the media", error)};
  return {};
}

EjectOutcome EjectDrive(wchar_t letter) {
  QuietErrors quiet;
  if (!IsEjectableDrive(letter)) {
    return {"failed", "This drive cannot be ejected."};
  }
  const wchar_t root[] = {letter, L':', L'\\', 0};
  if (GetDriveTypeW(root) == DRIVE_CDROM) return EjectMedia(letter);
  const HANDLE volume = OpenVolume(letter, 0);
  if (volume == INVALID_HANDLE_VALUE) {
    return {"failed", Win32Error("Cannot open the volume", GetLastError())};
  }
  STORAGE_DEVICE_NUMBER number{};
  const bool numbered = GetDeviceNumber(volume, &number);
  const DWORD error = numbered ? ERROR_SUCCESS : GetLastError();
  CloseHandle(volume);
  if (!numbered) {
    return {"failed", Win32Error("Cannot identify the disk", error)};
  }
  const DEVINST disk = FindDiskDevice(number);
  if (disk == 0) return {"failed", "Disk device not found."};
  const DEVINST removable = FindRemovableAncestor(disk);
  return removable == 0 ? EjectMedia(letter) : RequestDeviceEject(removable);
}

}  // namespace

bool IsEjectableDrive(wchar_t letter) {
  const wchar_t root[] = {letter, L':', L'\\', 0};
  switch (GetDriveTypeW(root)) {
    case DRIVE_REMOVABLE:
    case DRIVE_CDROM:
      return true;
    case DRIVE_FIXED:
      return !IsSystemDrive(letter) && IsOnExternalBus(letter);
    default:
      return false;
  }
}

void StartDiskEject(HWND window, const flutter::EncodableValue* arguments,
                    std::unique_ptr<Result> result) {
  const auto* path = arguments == nullptr
                         ? nullptr
                         : std::get_if<std::string>(arguments);
  if (path == nullptr || path->size() < 2 || (*path)[1] != ':' ||
      !std::isalpha(static_cast<unsigned char>((*path)[0]))) {
    result->Error("invalid_drive", "Expected a drive such as E:\\.");
    return;
  }
  const wchar_t letter =
      static_cast<wchar_t>(std::toupper(static_cast<unsigned char>((*path)[0])));
  auto* job = new EjectJob{std::move(result), {}};
  std::thread([window, letter, job] {
    job->outcome = EjectDrive(letter);
    if (!PostMessage(window, kDiskEjectDoneMessage, 0,
                     reinterpret_cast<LPARAM>(job))) {
      // The window is gone: nobody is waiting for the result anymore.
      delete job;
    }
  }).detach();
}

void HandleDiskEjectDone(LPARAM lparam) {
  std::unique_ptr<EjectJob> job(reinterpret_cast<EjectJob*>(lparam));
  if (job->outcome.code.empty()) {
    job->result->Success();
  } else {
    job->result->Error(job->outcome.code, job->outcome.message);
  }
}
