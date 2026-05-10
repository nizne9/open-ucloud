import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  ThemeMode toThemeMode() {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }

  String get storageValue {
    return switch (this) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    };
  }

  static AppThemeMode? fromStorageValue(String? value) {
    return switch (value) {
      'system' => AppThemeMode.system,
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => null,
    };
  }
}

abstract class OpenCloudThemeModeStorage {
  Future<String?> readThemeMode();

  Future<void> writeThemeMode(String value);
}

class SecureOpenCloudThemeModeStorage implements OpenCloudThemeModeStorage {
  SecureOpenCloudThemeModeStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _themeModeKey = 'open_cloud.theme_mode.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readThemeMode() {
    return _storage.read(key: _themeModeKey);
  }

  @override
  Future<void> writeThemeMode(String value) {
    return _storage.write(key: _themeModeKey, value: value);
  }
}

final themeModeStorageProvider = Provider<OpenCloudThemeModeStorage>(
  (_) => SecureOpenCloudThemeModeStorage(),
);

final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, AppThemeMode>(
      ThemeModeController.new,
    );

class ThemeModeController extends Notifier<AppThemeMode> {
  bool _bootstrapped = false;
  int _userSelectionRevision = 0;

  @override
  AppThemeMode build() => AppThemeMode.system;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;

    final storage = ref.read(themeModeStorageProvider);
    final bootstrapRevision = _userSelectionRevision;
    try {
      final value = await storage.readThemeMode();
      if (_userSelectionRevision == bootstrapRevision) {
        state = AppThemeModeX.fromStorageValue(value) ?? AppThemeMode.system;
      }
    } catch (_) {
      if (_userSelectionRevision == bootstrapRevision) {
        state = AppThemeMode.system;
      }
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _userSelectionRevision += 1;
    state = mode;

    final storage = ref.read(themeModeStorageProvider);
    try {
      await storage.writeThemeMode(mode.storageValue);
    } catch (_) {}
  }
}
