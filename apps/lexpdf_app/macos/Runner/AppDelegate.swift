import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var nativePdfChannel: FlutterMethodChannel?
  private var pendingPdfPath: String?
  private var flutterReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard
      let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "lexpdf/native_pdf_open",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "getInitialPdfPath":
        self.flutterReady = true
        result(self.pendingPdfPath)
        self.pendingPdfPath = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nativePdfChannel = channel
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    guard let path = filenames.first(where: { $0.lowercased().hasSuffix(".pdf") }) else {
      sender.reply(toOpenOrPrint: .failure)
      return
    }

    if flutterReady {
      nativePdfChannel?.invokeMethod("openPdfPath", arguments: path)
    } else {
      pendingPdfPath = path
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
