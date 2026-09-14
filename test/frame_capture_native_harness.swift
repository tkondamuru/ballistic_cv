// Minimal Flutter transport stubs; compile with FrameCapture.swift via the Python runner.
typealias FlutterBinaryMessenger = Int
typealias FlutterResult = (Any?) -> Void
struct FlutterMethodCall { let method: String; let arguments: Any? }
struct FlutterError { let code: String; let message: String?; let details: Any? }
let FlutterMethodNotImplemented = "notImplemented"
struct FlutterStandardTypedData { let data: Data }
final class FlutterMethodChannel {
  static var handler: ((FlutterMethodCall, @escaping FlutterResult) -> Void)?
  init(name: String, binaryMessenger: FlutterBinaryMessenger) {}
  func setMethodCallHandler(_ handler: @escaping (FlutterMethodCall, @escaping FlutterResult) -> Void) { Self.handler = handler }
}

func call(_ method: String, _ arguments: Any? = nil) -> Any? {
  var completed = false
  var value: Any?
  FlutterMethodChannel.handler!(FlutterMethodCall(method: method, arguments: arguments)) {
    value = $0; completed = true
  }
  let deadline = Date().addingTimeInterval(10)
  while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
  precondition(completed, "Native callback timeout")
  return value
}

let capture = FrameCapture()
capture.register(messenger: 0)
precondition(call("load") == nil)
precondition(call("start", ["objectName": "Test ball", "hsv": [60, 180, 180, 35, 85, 70, 255, 60, 255]]) == nil)
let pixels: [UInt8] = [0,0,255,255, 255,0,0,255, 9,9,9,9, 0,255,0,255, 255,255,255,255, 9,9,9,9]
let frame: [String: Any] = ["bytes": FlutterStandardTypedData(data: Data(pixels)), "width": 2, "height": 2, "stride": 12,
  "timeUs": 1000, "orientation": 0, "trail": [], "detection": ["detected": true]]
precondition(call("frame", frame) as? Int == 1)
precondition(call("finish", ["skipped": 2]) as? Int == 1)
let saved = call("load") as! [String: Any]
let entries = saved["frames"] as! [[String: Any]]
precondition(entries.count == 1 && entries[0]["number"] as? Int == 1)
let url = URL(fileURLWithPath: saved["directory"] as! String).appendingPathComponent(entries[0]["file"] as! String)
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
var output = [UInt8](repeating: 0, count: 16)
output.withUnsafeMutableBytes { bytes in
  let context = CGContext(data: bytes.baseAddress!, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
}
precondition(output == [255,0,0,255, 0,0,255,255, 0,255,0,255, 255,255,255,255], "BGRA conversion/padding/orientation mismatch: \(output)")
precondition(call("start", [:]) is FlutterError, "Must not overwrite a saved capture")
precondition(call("delete") == nil)
precondition(call("load") == nil)
precondition(!FileManager.default.fileExists(atPath: url.path))
precondition(call("start", [:]) == nil)
precondition(call("frame", ["width": 2]) is FlutterError)
precondition(call("finish") is FlutterError)
precondition(call("load") == nil)
print("Native frame capture passed: PNG colors/row padding, manifest, exclusive set, deletion, invalid frame and empty capture.")
