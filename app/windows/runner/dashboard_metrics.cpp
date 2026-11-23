#include "dashboard_metrics.h"

#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <utility>
#include <vector>

namespace {

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

int64_t Ticks(const FILETIME& time) {
  ULARGE_INTEGER ticks{};
  ticks.LowPart = time.dwLowDateTime;
  ticks.HighPart = time.dwHighDateTime;
  return static_cast<int64_t>(ticks.QuadPart);
}

Map Snapshot() {
  Map values;
  FILETIME idle{}, kernel{}, user{};
  if (GetSystemTimes(&idle, &kernel, &user)) {
    values.emplace(Value("idle"), Value(Ticks(idle)));
    values.emplace(Value("cpu"), Value(Ticks(kernel) + Ticks(user)));
  }

  MEMORYSTATUSEX memory{};
  memory.dwLength = sizeof(memory);
  if (GlobalMemoryStatusEx(&memory)) {
    values.emplace(Value("memoryFree"),
                   Value(static_cast<int64_t>(memory.ullAvailPhys)));
    values.emplace(Value("memoryTotal"),
                   Value(static_cast<int64_t>(memory.ullTotalPhys)));
  }

  wchar_t system[MAX_PATH]{};
  const UINT system_length = GetWindowsDirectoryW(system, MAX_PATH);
  ULARGE_INTEGER disk_free{}, disk_total{};
  if (system_length > 0 && system_length < MAX_PATH &&
      GetDiskFreeSpaceExW(system, &disk_free, &disk_total, nullptr)) {
    values.emplace(Value("diskFree"), Value(static_cast<int64_t>(disk_free.QuadPart)));
    values.emplace(Value("diskTotal"), Value(static_cast<int64_t>(disk_total.QuadPart)));
  }

  PMIB_IF_TABLE2 table = nullptr;
  if (GetIfTable2(&table) == NO_ERROR) {
    std::unique_ptr<MIB_IF_TABLE2, decltype(&FreeMibTable)> owned(table, FreeMibTable);
    Map interfaces;
    for (ULONG index = 0; index < table->NumEntries; ++index) {
      const auto& adapter = table->Table[index];
      if (!adapter.InterfaceAndOperStatusFlags.HardwareInterface ||
          adapter.OperStatus != IfOperStatusUp) {
        continue;
      }
      interfaces.emplace(
          Value(static_cast<int64_t>(adapter.InterfaceIndex)),
          Value(flutter::EncodableList{
              Value(static_cast<int64_t>(adapter.InOctets)),
              Value(static_cast<int64_t>(adapter.OutOctets)),
          }));
    }
    values.emplace(Value("interfaces"), Value(std::move(interfaces)));
  }

  UINT count = 0;
  if (GetRawInputDeviceList(nullptr, &count, sizeof(RAWINPUTDEVICELIST)) !=
      static_cast<UINT>(-1)) {
    // Hotplug can change the count between the two calls.
    std::vector<RAWINPUTDEVICELIST> devices(count);
    const UINT found = count == 0
        ? 0 : GetRawInputDeviceList(devices.data(), &count, sizeof(RAWINPUTDEVICELIST));
    if (found != static_cast<UINT>(-1) && found <= devices.size()) {
      const auto end = devices.begin() + found;
      const auto count_type = [&](DWORD type) {
        return static_cast<int32_t>(std::count_if(devices.begin(), end,
            [type](const auto& device) { return device.dwType == type; }));
      };
      values.emplace(Value("keyboards"), Value(count_type(RIM_TYPEKEYBOARD)));
      values.emplace(Value("mice"), Value(count_type(RIM_TYPEMOUSE)));
    }
  }
  return values;
}

}  // namespace

void RegisterDashboardMetrics(flutter::BinaryMessenger* messenger) {
  flutter::MethodChannel<Value> channel(
      messenger, "endlessnet/dashboard",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "snapshot") {
      result->Success(Value(Snapshot()));
    } else {
      result->NotImplemented();
    }
  });
}
