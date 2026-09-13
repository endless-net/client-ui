import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var diagnosticsDestination: DiagnosticsDestination?
  private var deadlineNotifications: DeadlineNotifications?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    diagnosticsDestination = DiagnosticsDestination(
      messenger: flutterViewController.engine.binaryMessenger, window: self)
    deadlineNotifications = DeadlineNotifications(
      messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }
}

private final class DeadlineNotifications: NSObject, UNUserNotificationCenterDelegate {
  private weak var window: NSWindow?
  private let center = UNUserNotificationCenter.current()
  private let channel: FlutterMethodChannel
  private var observer: NSObjectProtocol?
  private var receipts: [String] = []
  private var closed = false
  private var requesting = false

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    channel = FlutterMethodChannel(name: "endlessnet/ui-notifications", binaryMessenger: messenger)
    super.init()
    center.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.closed else { result("unavailable"); return }
      if call.method == "requestPermission" {
        guard call.arguments == nil, !self.requesting else { result("unavailable"); return }
        self.requesting = true
        self.center.requestAuthorization(options: [.alert]) { [weak self] granted, error in
          DispatchQueue.main.async {
            guard let self = self, !self.closed else { result("unavailable"); return }
            self.requesting = false
            result(error != nil ? "unavailable" : granted ? "granted" : "denied")
          }
        }
        return
      }
      guard call.method == "deliver" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: String], args.count == 2,
            args["title"] == "EndlessNet", let body = args["body"],
            !body.isEmpty, body.utf8.count <= 2048, !body.contains("\0") else {
        result("failed"); return
      }
      self.center.getNotificationSettings { [weak self] settings in
        DispatchQueue.main.async {
          guard let self = self, !self.closed else { result("unavailable"); return }
          guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else {
            result("permissionDenied"); return
          }
          let content = UNMutableNotificationContent()
          content.title = "EndlessNet"
          content.body = body
          let id = "endlessnet-deadline-" + UUID().uuidString
          self.receipts.append(id)
          if self.receipts.count > 64 { self.receipts.removeFirst() }
          self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { [weak self] error in
            DispatchQueue.main.async {
              guard let self = self, !self.closed else { result("unavailable"); return }
              if error != nil { self.receipts.removeAll { $0 == id } }
              result(error == nil ? "delivered" : "failed")
            }
          }
        }
      }
    }
    observer = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in self?.shutdown() }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.closed,
            self.receipts.contains(notification.request.identifier) else { completionHandler([]); return }
      completionHandler([.banner, .list])
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    DispatchQueue.main.async { [weak self] in
      defer { completionHandler() }
      guard let self = self, !self.closed,
            response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let index = self.receipts.firstIndex(of: response.notification.request.identifier) else { return }
      self.receipts.remove(at: index)
      self.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func shutdown() {
    closed = true
    center.removePendingNotificationRequests(withIdentifiers: receipts)
    receipts.removeAll()
    if center.delegate === self { center.delegate = nil }
    channel.setMethodCallHandler(nil)
  }
  deinit {
    shutdown()
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
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
