#include "ui_tray_host.h"

#include <cstdlib>

void Check(bool condition) {
  if (!condition) std::abort();
}

int main() {
  Check(UiTrayIconBoundsAvailable(true, -100, -200, -80, -180));
  Check(!UiTrayIconBoundsAvailable(false, 0, 0, 20, 20));
  Check(!UiTrayIconBoundsAvailable(true, 0, 0, 0, 0));
  Check(!UiTrayIconBoundsAvailable(true, 20, 0, 0, 20));
  Check(!UiTrayIconBoundsAvailable(true, 0, 20, 20, 0));
  UiTrayHostState host;
  Check(!host.Available(true));
  host.Initialize(0);
  host.OnMessage(0);
  Check(!host.Available(true));
  host.Initialize(0xc123);
  Check(host.Available(true));
  Check(!host.IconAvailable(true, false));
  Check(!host.IconAvailable(false, true));
  Check(host.IconAvailable(true, true));
  Check(!host.Available(false));
  host.OnMessage(0x42);
  Check(host.Available(true));
  host.OnMessage(0xc123);
  Check(!host.IconAvailable(true, true));
  Check(!host.Available(true));
  Check(!host.Available(false));
  host.OnMessage(0x42);
  Check(!host.Available(true));
  // Prepare before registration; a restart during registration still wins.
  host.PrepareRegistration();
  Check(host.Available(true));
  host.OnMessage(0xc123);
  Check(!host.Available(true));
  // A new native UI lifetime can establish its own readiness.
  UiTrayHostState replacement;
  replacement.Initialize(0xc123);
  Check(replacement.Available(true));
  Check(!host.Available(true));
}
