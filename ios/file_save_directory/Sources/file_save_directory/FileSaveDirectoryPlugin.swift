import UIKit
import Flutter
import MobileCoreServices

public class FileSaveDirectoryPlugin: NSObject, FlutterPlugin {
  private var pendingFlutterResult: FlutterResult?
  private var tempFileURL: URL?
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.filesave/file_save_directory", binaryMessenger: registrar.messenger())
    let instance = FileSaveDirectoryPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "saveFileWithPicker":
      guard let args = call.arguments as? [String: Any],
            let fileName = args["fileName"] as? String,
            let fileBytes = args["fileBytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
        return
      }
      saveFileWithPicker(fileName: fileName, fileData: fileBytes.data, result: result)
      
    case "createFolder":
      guard let args = call.arguments as? [String: Any],
            let folderName = args["folderName"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing folder name", details: nil))
        return
      }
      createFolder(folderName: folderName, result: result)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func saveFileWithPicker(fileName: String, fileData: Data, result: @escaping FlutterResult) {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    do {
      try fileData.write(to: tempURL)
      self.tempFileURL = tempURL
      self.pendingFlutterResult = result
    } catch {
      result(FlutterError(code: "FILE_WRITE_FAILED", message: "Could not write temp file", details: error.localizedDescription))
      return
    }

    // Use iOS 11+ compatible API
    let documentPicker = UIDocumentPickerViewController(url: tempURL, in: .exportToService)
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    
    // Get the root view controller to present the picker
    if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
      rootViewController.present(documentPicker, animated: true, completion: nil)
    } else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Could not present document picker", details: nil))
    }
  }
  
  private func createFolder(folderName: String, result: @escaping FlutterResult) {
    // Use iOS 11+ compatible API for folder creation
    let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    
    // Store the folder creation request
    self.pendingFlutterResult = result
    
    // Get the root view controller to present the picker
    if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
      rootViewController.present(documentPicker, animated: true, completion: nil)
    } else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Could not present document picker", details: nil))
    }
  }
}

// MARK: - UIDocumentPickerDelegate
extension FileSaveDirectoryPlugin: UIDocumentPickerDelegate {
  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      pendingFlutterResult?(FlutterError(code: "NO_URL_SELECTED", message: "No URL selected", details: nil))
      cleanup()
      return
    }
    
    // If we have a temp file, move it to the selected location
    if let tempURL = tempFileURL {
      do {
        let destinationURL = url.appendingPathComponent(tempURL.lastPathComponent)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        pendingFlutterResult?(true)
      } catch {
        pendingFlutterResult?(FlutterError(code: "FILE_MOVE_FAILED", message: "Could not move file to destination", details: error.localizedDescription))
      }
    } else {
      // This was a folder creation request
      pendingFlutterResult?(true)
    }
    
    cleanup()
  }
  
  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingFlutterResult?(FlutterError(code: "CANCELLED", message: "User cancelled the operation", details: nil))
    cleanup()
  }
  
  private func cleanup() {
    pendingFlutterResult = nil
    tempFileURL = nil
  }
} 