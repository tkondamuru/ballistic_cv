import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let frameCapture = FrameCapture()
  private let trajectoryStorage = TrajectoryStorage()
  private let consoleQueue = DispatchQueue(label: "ballistic.console")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ConsoleLog") {
      let channel = FlutterMethodChannel(name: "ballistic/console", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [self] call, result in
        guard call.method == "line", let line = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        consoleQueue.async {
          FileHandle.standardError.write(Data((line + "\n").utf8))
          DispatchQueue.main.async { result(nil) }
        }
      }
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrajectoryStorage") {
      trajectoryStorage.register(messenger: registrar.messenger()) { [weak self] in
        self?.window?.rootViewController ?? UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
          .first { $0.isKeyWindow }?.rootViewController
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FrameCapture") {
      frameCapture.register(messenger: registrar.messenger())
    }
  }
}

/// Append-only coordinate sessions survive disconnection and partial app exits.
/// All file work is serialized off the UI thread; sharing uses the system sheet.
final class TrajectoryStorage {
  private let queue = DispatchQueue(label: "ballistic.trajectory")
  private var file: FileHandle?
  private var activeName: String?
  private var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TrajectorySessions", isDirectory: true)
  }
  func register(messenger: FlutterBinaryMessenger, presenter: @escaping () -> UIViewController?) {
    let channel = FlutterMethodChannel(name: "ballistic/trajectory", binaryMessenger: messenger)
    channel.setMethodCallHandler { [self] call, result in
      if call.method == "share" {
        guard let name = call.arguments as? String, name == URL(fileURLWithPath: name).lastPathComponent,
              name.hasSuffix(".jsonl"), name != activeName,
              FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path),
              var controller = presenter() else {
          result(FlutterError(code: "share", message: "Recording is unavailable or still active", details: nil)); return
        }
        while let presented = controller.presentedViewController { controller = presented }
        let sheet = UIActivityViewController(activityItems: [root.appendingPathComponent(name)], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = controller.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        controller.present(sheet, animated: true)
        result(nil); return
      }
      queue.async {
        do {
          let value = try self.handle(call)
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "trajectory", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }
  private func handle(_ call: FlutterMethodCall) throws -> Any? {
    guard #available(iOS 13.4, *) else { throw NSError(domain: "Coordinate recording requires iOS 13.4 or later", code: 3) }
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    var directory = root
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    switch call.method {
    case "start":
      guard file == nil, let header = call.arguments as? String else { throw NSError(domain: "Already recording", code: 1) }
      let name = "thud-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).jsonl"
      let url = root.appendingPathComponent(name)
      try Data((header + "\n").utf8).write(to: url, options: .atomic)
      file = try FileHandle(forWritingTo: url); try file?.seekToEnd(); activeName = name
      return name
    case "append":
      guard let handle = file, let text = call.arguments as? String else { throw NSError(domain: "No active recording", code: 2) }
      try handle.write(contentsOf: Data(text.utf8)); return nil
    case "finish":
      guard let handle = file, let text = call.arguments as? String else { throw NSError(domain: "No active recording", code: 2) }
      defer { try? handle.close(); file = nil; activeName = nil }
      try handle.write(contentsOf: Data((text + "\n").utf8)); try handle.synchronize(); return nil
    case "list":
      return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension == "jsonl" && $0.lastPathComponent != activeName }.sorted { $0.lastPathComponent > $1.lastPathComponent }.map {
        ["name": $0.lastPathComponent, "bytes": (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0] as [String: Any]
      }
    default: return FlutterMethodNotImplemented
    }
  }
}
