import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var nativePdfChannel: FlutterMethodChannel?
  private var pendingPdfPaths: [String] = []
  private var flutterReady = false
  private var deliveringPdf = false

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
        let initialPath = self.pendingPdfPaths.isEmpty ? nil : self.pendingPdfPaths.removeFirst()
        result(initialPath)
        self.deliverPendingPdfIfPossible()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nativePdfChannel = channel
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    let paths = filenames.compactMap { sourcePath -> String? in
      guard sourcePath.lowercased().hasSuffix(".pdf") else { return nil }
      return materializePdf(sourcePath)
    }

    guard !paths.isEmpty else {
      sender.reply(toOpenOrPrint: .failure)
      return
    }

    pendingPdfPaths.append(contentsOf: paths)
    deliverPendingPdfIfPossible()
    sender.reply(toOpenOrPrint: .success)
  }

  private func deliverPendingPdfIfPossible() {
    guard flutterReady, !deliveringPdf, !pendingPdfPaths.isEmpty else { return }
    guard let channel = nativePdfChannel else { return }

    deliveringPdf = true
    let path = pendingPdfPaths.removeFirst()
    channel.invokeMethod("openPdfPath", arguments: path) { [weak self] _ in
      guard let self else { return }
      self.deliveringPdf = false
      self.deliverPendingPdfIfPossible()
    }
  }

  private func materializePdf(_ sourcePath: String) -> String? {
    let fileManager = FileManager.default
    let sourceUrl = URL(fileURLWithPath: sourcePath)

    guard fileManager.fileExists(atPath: sourceUrl.path) else { return nil }
    let didAccess = sourceUrl.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        sourceUrl.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let appSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let targetDir = appSupport
        .appendingPathComponent("LexPDF", isDirectory: true)
        .appendingPathComponent("native_open", isDirectory: true)
      try fileManager.createDirectory(
        at: targetDir,
        withIntermediateDirectories: true,
        attributes: nil
      )

      let safeName = sourceUrl.lastPathComponent.replacingOccurrences(
        of: "[^A-Za-z0-9._-]",
        with: "_",
        options: .regularExpression
      )
      let key = stablePathKey(sourceUrl.path)
      let target = targetDir.appendingPathComponent("\(key)_\(safeName)")

      if
        let attributes = try? fileManager.attributesOfItem(atPath: target.path),
        let size = attributes[.size] as? NSNumber,
        size.int64Value > 0
      {
        return target.path
      }

      let temporary = targetDir.appendingPathComponent(".\(UUID().uuidString).tmp")
      defer { try? fileManager.removeItem(at: temporary) }
      try fileManager.copyItem(at: sourceUrl, to: temporary)

      let attributes = try fileManager.attributesOfItem(atPath: temporary.path)
      guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
        return nil
      }

      if fileManager.fileExists(atPath: target.path) {
        _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
      } else {
        try fileManager.moveItem(at: temporary, to: target)
      }
      return target.path
    } catch {
      return nil
    }
  }

  private func stablePathKey(_ path: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in path.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1099511628211
    }
    return String(hash, radix: 16)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
