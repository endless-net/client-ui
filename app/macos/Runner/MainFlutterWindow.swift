import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var diagnosticsDestination: DiagnosticsDestination?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    diagnosticsDestination = DiagnosticsDestination(
      messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }
}

private final class DiagnosticsDestination {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var closeObserver: NSObjectProtocol?
  private var panel: NSOpenPanel?
  private var pending: FlutterResult?
  private var grant: (id: String, url: URL)?
  private var closed = false

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    channel = FlutterMethodChannel(name: "endlessnet/ui-diagnostics-macos", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.closed else {
        result(FlutterError(code: "destination_unavailable", message: "Destination unavailable", details: nil))
        return
      }
      switch call.method {
      case "chooseDirectory":
        guard call.arguments == nil else {
          result(FlutterError(code: "invalid_arguments", message: "No arguments expected", details: nil))
          return
        }
        self.choose(result)
      case "releaseDirectory":
        guard let id = call.arguments as? String, id == self.grant?.id else {
          result(FlutterError(code: "invalid_lease", message: "Invalid destination lease", details: nil))
          return
        }
        self.release()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in self?.shutdown() }
  }

  private func choose(_ result: @escaping FlutterResult) {
    guard let window = window, pending == nil, grant == nil else {
      result(FlutterError(code: "destination_unavailable", message: "Destination unavailable", details: nil))
      return
    }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    self.panel = panel
    pending = result
    panel.beginSheetModal(for: window) { [weak self, weak panel] response in
      let selectedURL = panel?.url
      guard let self = self, !self.closed, let completion = self.pending else {
        if response == .OK { selectedURL?.stopAccessingSecurityScopedResource() }
        return
      }
      self.pending = nil
      self.panel = nil
      guard response == .OK else { completion(nil); return }
      guard let url = selectedURL, url.isFileURL else {
        completion(FlutterError(code: "destination_unavailable", message: "Destination unavailable", details: nil))
        return
      }
      // NSOpenPanel starts the security-scoped grant. Retain until explicit release.
      let id = UUID().uuidString
      self.grant = (id, url)
      completion(["lease": id, "path": url.path])
    }
  }

  private func release() {
    grant?.url.stopAccessingSecurityScopedResource()
    grant = nil
  }

  private func shutdown() {
    if closed { return }
    closed = true
    panel?.cancel(nil)
    panel = nil
    let completion = pending
    pending = nil
    completion?(nil)
    release()
    channel.setMethodCallHandler(nil)
  }

  deinit {
    shutdown()
    if let observer = closeObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
