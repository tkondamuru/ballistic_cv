import Flutter
import Foundation
import CoreGraphics
import ImageIO

/// One private capture, lossless PNG frames, and a serial disk writer.
final class FrameCapture {
  private let queue = DispatchQueue(label: "ballistic.frameCapture")
  private var active = false
  private var manifest: [String: Any] = [:]
  private var frames: [[String: Any]] = []
  private var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("BallisticScans", isDirectory: true)
  }
  private var saved: URL { root.appendingPathComponent("saved", isDirectory: true) }
  private var pending: URL { root.appendingPathComponent("pending", isDirectory: true) }
  private func fail(_ text: String) -> NSError {
    NSError(domain: "FrameCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
  }
  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ballistic/frames", binaryMessenger: messenger)
    channel.setMethodCallHandler { [self] call, result in
      queue.async {
        do {
          let value = try self.handle(call)
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "capture", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }
  private func handle(_ call: FlutterMethodCall) throws -> Any? {
    let fm = FileManager.default
    switch call.method {
    case "load":
      // Incomplete captures from a terminated app are never presented as saved.
      if !active && fm.fileExists(atPath: pending.path) { try fm.removeItem(at: pending) }
      guard fm.fileExists(atPath: saved.path) else { return nil }
      guard var data = try JSONSerialization.jsonObject(with: Data(contentsOf: saved.appendingPathComponent("manifest.json"))) as? [String: Any],
        let entries = data["frames"] as? [[String: Any]], !entries.isEmpty else { throw fail("Saved capture is incomplete; delete it and capture again") }
      data["directory"] = saved.path
      return data
    case "start":
      guard !active && !fm.fileExists(atPath: saved.path) else { throw fail("Delete the existing scanned frames before capturing again") }
      if fm.fileExists(atPath: pending.path) { try fm.removeItem(at: pending) }
      try fm.createDirectory(at: pending, withIntermediateDirectories: true)
      var location = root
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try location.setResourceValues(values)
      manifest = call.arguments as? [String: Any] ?? [:]
      frames = []; active = true
      return nil
    case "frame":
      guard active, frames.count < 600, var data = call.arguments as? [String: Any],
        let pixels = data.removeValue(forKey: "bytes") as? FlutterStandardTypedData,
        let w = data["width"] as? Int, let h = data["height"] as? Int,
        let stride = data["stride"] as? Int,
        w > 0, h > 0, w <= 4096, h <= 4096, stride >= w * 4,
        pixels.data.count >= stride * h else { throw fail("Invalid capture frame") }
      guard let provider = CGDataProvider(data: pixels.data as CFData),
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw fail("Could not encode frame") }
      let filename = String(format: "%04d.png", frames.count + 1)
      let path = pending.appendingPathComponent(filename)
      guard let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil) else { throw fail("Could not create frame file") }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else {
        try? fm.removeItem(at: path)
        throw fail("Could not write frame; storage may be full")
      }
      data["file"] = filename; data["number"] = frames.count + 1
      frames.append(data)
      return frames.count
    case "finish":
      guard active else { throw fail("No capture in progress") }
      defer { active = false; frames = []; manifest = [:] }
      guard !frames.isEmpty else {
        try? fm.removeItem(at: pending)
        throw fail("No frames captured")
      }
      manifest["frames"] = frames
      manifest["summary"] = call.arguments as? [String: Any] ?? [:]
      try JSONSerialization.data(withJSONObject: manifest).write(to: pending.appendingPathComponent("manifest.json"), options: .atomic)
      try fm.moveItem(at: pending, to: saved)
      return frames.count
    case "delete":
      guard !active else { throw fail("Capture is still running") }
      if fm.fileExists(atPath: saved.path) { try fm.removeItem(at: saved) }
      if fm.fileExists(atPath: pending.path) { try fm.removeItem(at: pending) }
      return nil
    default: return FlutterMethodNotImplemented
    }
  }
}
