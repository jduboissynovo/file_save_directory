Pod::Spec.new do |s|
    s.name             = 'file_save_directory'
    s.version          = '0.0.1'
    s.summary          = 'A Flutter plugin for saving files to directory'
    s.description      = <<-DESC
  A Flutter plugin that provides functionality to save files to a directory.
                         DESC
    s.homepage         = 'https://github.com/yourusername/file_save_directory'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'Your Company' => 'your.email@example.com' }
    s.source           = { :path => '.' }
    s.source_files     = 'file_save_directory/Sources/file_save_directory/**/*'
    s.dependency 'Flutter'
    s.platform = :ios, '15.0'
    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
    s.swift_version = '5.0'
  end