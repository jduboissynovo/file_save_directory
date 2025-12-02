import 'dart:io';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:open_file/open_file.dart'; // Add this dependency
import 'save_location.dart';

class FileSaveDirectory {
  static const MethodChannel _channel =
      MethodChannel('com.filesave/file_save_directory');

  FileSaveDirectory._();
  static final FileSaveDirectory instance = FileSaveDirectory._();

  /// Save file to specified location
  Future<FileSaveResult> saveFile({
    required String fileName,
    required List<int> fileBytes,
    SaveLocation location = SaveLocation.downloads,
    bool openAfterSave = true, // Default to true
  }) async {
    try {
      FileSaveResult result;
      switch (location) {
        case SaveLocation.downloads:
          result = await _saveToDownloads(fileName, fileBytes);
          break;
        case SaveLocation.documents:
          result = await _saveToDocuments(fileName, fileBytes);
          break;
        case SaveLocation.music:
          result = await _saveToMusic(fileName, fileBytes);
          break;
        case SaveLocation.videos:
          result = await _saveToVideos(fileName, fileBytes);
          break;
        case SaveLocation.appDocuments:
          result = await _saveToAppDocuments(fileName, fileBytes);
          break;
      }

      // Open file if requested and save was successful
      if (result.success && openAfterSave && result.path != null) {
        await _openFile(result.path!);
      }

      return result;
    } catch (e) {
      log('Error saving file: $e');
      return FileSaveResult(
        success: false,
        error: 'Unexpected error: $e',
        path: null,
      );
    }
  }

  /// Open file using default system app
  Future<void> _openFile(String filePath) async {
    try {
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        log('Failed to open file: ${result.message}');
      }
    } catch (e) {
      log('Error opening file: $e');
    }
  }

  Future<FileSaveResult> _saveToDownloads(
      String fileName, List<int> fileBytes) async {
    if (Platform.isAndroid) {
      return await _saveToAndroidFolder(fileName, fileBytes, 'Downloads');
    } else if (Platform.isIOS) {
      // iOS doesn't have a public Downloads folder, save to Documents instead
      return await _saveToIOSDocuments(fileName, fileBytes);
    }
    return FileSaveResult(
      success: false,
      error: 'Platform not supported',
      path: null,
    );
  }

  Future<FileSaveResult> _saveToDocuments(
      String fileName, List<int> fileBytes) async {
    if (Platform.isAndroid) {
      return await _saveToAndroidFolder(fileName, fileBytes, 'Documents');
    } else if (Platform.isIOS) {
      return await _saveToIOSDocuments(fileName, fileBytes);
    }
    return FileSaveResult(
      success: false,
      error: 'Platform not supported',
      path: null,
    );
  }

  Future<FileSaveResult> _saveToMusic(
      String fileName, List<int> fileBytes) async {
    if (Platform.isAndroid) {
      return await _saveToAndroidFolder(fileName, fileBytes, 'Music');
    } else if (Platform.isIOS) {
      // iOS doesn't have a public Music folder accessible to apps
      // Save to app's Music directory or use document picker
      return await _saveToIOSMusic(fileName, fileBytes);
    }
    return FileSaveResult(
      success: false,
      error: 'Platform not supported',
      path: null,
    );
  }

  Future<FileSaveResult> _saveToVideos(
      String fileName, List<int> fileBytes) async {
    if (Platform.isAndroid) {
      return await _saveToAndroidFolder(fileName, fileBytes, 'Videos');
    } else if (Platform.isIOS) {
      // iOS doesn't have a public Videos folder accessible to apps
      // Save to app's Videos directory or use document picker
      return await _saveToIOSVideos(fileName, fileBytes);
    }
    return FileSaveResult(
      success: false,
      error: 'Platform not supported',
      path: null,
    );
  }

  Future<FileSaveResult> _saveToAppDocuments(
      String fileName, List<int> fileBytes) async {
    try {
      Directory dir = await getApplicationDocumentsDirectory();
      final file = await _getUniqueFile(dir.path, fileName);
      await file.writeAsBytes(fileBytes);

      log('File saved in app documents directory: ${file.path}');

      return FileSaveResult(
        success: true,
        path: file.path,
        message: 'File saved successfully in app documents',
      );
    } catch (e) {
      return FileSaveResult(
        success: false,
        error: 'Failed to save file: $e',
        path: null,
      );
    }
  }

  Future<FileSaveResult> _saveToAndroidFolder(
      String fileName, List<int> fileBytes, String folder) async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    // Handle permissions based on Android version
    bool permissionGranted = await _requestAndroidPermissions(sdkInt);

    if (!permissionGranted) {
      return FileSaveResult(
        success: false,
        error:
            'Storage permission denied. Please grant permission from app settings.',
        path: null,
        needsPermission: true,
      );
    }

    try {
      if (sdkInt >= 33) {
        // Android 13+, use MediaStore
        return await _saveViaMediaStore(fileName, fileBytes, folder);
      } else {
        // Older Android versions, save directly
        return await _saveDirectly(fileName, fileBytes, folder);
      }
    } catch (e) {
      log('Error saving to $folder: $e');
      return FileSaveResult(
        success: false,
        error: 'Failed to save file: $e',
        path: null,
      );
    }
  }

  Future<bool> _requestAndroidPermissions(int sdkInt) async {
    if (sdkInt >= 30) {
      return true; // Doesn't need storage permission for MediaStore
    } else {
      var status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  Future<FileSaveResult> _saveDirectly(
      String fileName, List<int> fileBytes, String folder) async {
    try {
      String folderPath;
      switch (folder) {
        case 'Documents':
          folderPath = '/storage/emulated/0/Documents';
          break;
        case 'Music':
          folderPath = '/storage/emulated/0/Music';
          break;
        case 'Videos':
          folderPath =
              '/storage/emulated/0/Movies'; // Android uses Movies folder
          break;
        default:
          folderPath = '/storage/emulated/0/Download';
      }

      Directory targetDir = Directory(folderPath);

      if (!targetDir.existsSync()) {
        Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir == null) {
          return FileSaveResult(
            success: false,
            error: 'Cannot access storage',
            path: null,
          );
        }
        targetDir = Directory('${externalDir.path}/$folder');
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
      }

      final file = await _getUniqueFile(targetDir.path, fileName);
      await file.writeAsBytes(fileBytes);

      return FileSaveResult(
        success: true,
        path: file.path,
        message: 'File saved successfully in $folder',
      );
    } catch (e) {
      return FileSaveResult(
        success: false,
        error: 'Failed to save file: $e',
        path: null,
      );
    }
  }

  Future<FileSaveResult> _saveViaMediaStore(
      String fileName, List<int> fileBytes, String folder) async {
    try {
      final bool result = await _channel.invokeMethod('saveFile', {
        'fileName': fileName,
        'fileBytes': Uint8List.fromList(fileBytes),
        'folder': folder,
      });

      if (result) {
        return FileSaveResult(
          success: true,
          path: '$folder/$fileName',
          message: 'File saved successfully in $folder',
        );
      } else {
        return FileSaveResult(
          success: false,
          error: 'Failed to save file via MediaStore',
          path: null,
        );
      }
    } catch (e) {
      log('Error with MediaStore: $e');
      // Fallback to direct method
      return await _saveDirectly(fileName, fileBytes, folder);
    }
  }

  Future<FileSaveResult> _saveToIOSDocuments(
      String fileName, List<int> fileBytes) async {
    try {
      final bool result = await _channel.invokeMethod(
        'saveFileWithPicker',
        {
          'fileName': fileName,
          'fileBytes': fileBytes,
        },
      );

      return FileSaveResult(
        success: result,
        message: result ? 'File saved via document picker' : 'Failed to save',
        path: null,
      );
    } catch (e) {
      return FileSaveResult(
        success: false,
        error: 'iOS Save Picker Error: $e',
        path: null,
      );
    }
  }

  Future<FileSaveResult> _saveToIOSMusic(
      String fileName, List<int> fileBytes) async {
    try {
      // iOS doesn't allow direct access to the Music library for third-party apps
      // We have two options:
      // 1. Save to app's private music directory
      // 2. Use document picker (same as documents)

      // Option 1: Save to app's music directory
      Directory appDir = await getApplicationDocumentsDirectory();
      String musicDirPath = '${appDir.path}/Music';
      Directory musicDir = Directory(musicDirPath);

      if (!musicDir.existsSync()) {
        musicDir.createSync(recursive: true);
      }

      final file = await _getUniqueFile(musicDir.path, fileName);
      await file.writeAsBytes(fileBytes);

      log('File saved in app music directory: ${file.path}');

      return FileSaveResult(
        success: true,
        path: file.path,
        message:
            'File saved in app\'s Music folder. Note: iOS apps cannot directly save to the system Music library.',
      );

      // Option 2: Use document picker (uncomment if preferred)
      // return await _saveToIOSDocuments(fileName, fileBytes);
    } catch (e) {
      return FileSaveResult(
        success: false,
        error: 'Failed to save to Music folder: $e',
        path: null,
      );
    }
  }

  Future<FileSaveResult> _saveToIOSVideos(
      String fileName, List<int> fileBytes) async {
    try {
      // iOS doesn't allow direct access to the Videos library for third-party apps
      // We have two options:
      // 1. Save to app's private videos directory
      // 2. Use document picker (same as documents)

      // Option 1: Save to app's videos directory
      Directory appDir = await getApplicationDocumentsDirectory();
      String videosDirPath = '${appDir.path}/Videos';
      Directory videosDir = Directory(videosDirPath);

      if (!videosDir.existsSync()) {
        videosDir.createSync(recursive: true);
      }

      final file = await _getUniqueFile(videosDir.path, fileName);
      await file.writeAsBytes(fileBytes);

      log('File saved in app videos directory: ${file.path}');

      return FileSaveResult(
        success: true,
        path: file.path,
        message:
            'File saved in app\'s Videos folder. Note: iOS apps cannot directly save to the system Videos library.',
      );

      // Option 2: Use document picker (uncomment if preferred)
      // return await _saveToIOSDocuments(fileName, fileBytes);
    } catch (e) {
      return FileSaveResult(
        success: false,
        error: 'Failed to save to Videos folder: $e',
        path: null,
      );
    }
  }

  Future<File> _getUniqueFile(String dirPath, String fileName) async {
    String filePath = path.join(dirPath, fileName);
    File file = File(filePath);
    int counter = 1;

    while (await file.exists()) {
      final fileNameWithoutExtension = path.basenameWithoutExtension(fileName);
      final extension = path.extension(fileName);
      final newFileName = '$fileNameWithoutExtension($counter)$extension';
      filePath = path.join(dirPath, newFileName);
      file = File(filePath);
      counter++;
    }

    return file;
  }

  /// Open app settings for permission management
  Future<void> openAppSettings() async {
    await openAppSettings();
  }

  /// Check if the file is an audio file based on its extension
  bool isAudioFile(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    const audioExtensions = [
      '.mp3',
      '.wav',
      '.m4a',
      '.flac',
      '.ogg',
      '.aac',
      '.wma',
      '.opus'
    ];
    return audioExtensions.contains(extension);
  }

  /// Check if the file is a video file based on its extension
  bool isVideoFile(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    const videoExtensions = [
      '.mp4',
      '.avi',
      '.mkv',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.m4v',
      '.3gp',
      '.mpeg'
    ];
    return videoExtensions.contains(extension);
  }
}

/// Result class for file save operations
class FileSaveResult {
  final bool success;
  final String? path;
  final String? message;
  final String? error;
  final bool needsPermission;

  FileSaveResult({
    required this.success,
    this.path,
    this.message,
    this.error,
    this.needsPermission = false,
  });

  @override
  String toString() {
    return 'FileSaveResult(success: $success, path: $path, message: $message, error: $error, needsPermission: $needsPermission)';
  }
}
