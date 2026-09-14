#include "ui_tray_host.h"

#include <cstdlib>

void Check(bool condition) {
  if (!condition) std::abort();
}

int main() {
  UiTrayHostState host;
  Check(!host.Available(true));
  host.Initialize(0);
  host.OnMessage(0);
  Check(!host.Available(true));
  host.Initialize(0xc123);
  Check(host.Available(true));
  Check(!host.Available(false));
  host.OnMessage(0x42);
  Check(host.Available(true));
  host.OnMessage(0xc123);
  Check(!host.Available(true));
  Check(!host.Available(false));
  host.OnMessage(0x42);
  Check(!host.Available(true));
  // A new native UI lifetime can establish its own readiness.
  UiTrayHostState replacement;
  replacement.Initialize(0xc123);
  Check(replacement.Available(true));
  Check(!host.Available(true));
}
