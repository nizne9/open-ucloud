import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_ucloud_client/src/open_ucloud_gateway.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolves macOS bundled dylib from app executable path', () {
    final executablePath = p.join(
      'Open UCloud.app',
      'Contents',
      'MacOS',
      'Open UCloud',
    );

    final libraryPath = bundledMacOsLibraryPathForExecutable(executablePath);

    expect(
      libraryPath,
      p.join(
        'Open UCloud.app',
        'Contents',
        'Frameworks',
        'libopen_ucloud_ffi.dylib',
      ),
    );
  });

  test('macOS release runner bundles a universal Rust dylib', () {
    final script = File(
      p.join('macos', 'Runner', 'Scripts', 'bundle_open_ucloud_ffi.sh'),
    ).readAsStringSync();

    expect(script, contains('aarch64-apple-darwin'));
    expect(script, contains('x86_64-apple-darwin'));
    expect(script, contains('lipo -create'));
  });
}
