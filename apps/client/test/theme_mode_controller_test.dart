import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/theme_mode_controller.dart';

void main() {
  test('restores stored theme mode values', () async {
    final storage = MemoryThemeModeStorage(value: 'dark');
    final container = _container(storage);
    addTearDown(container.dispose);

    await container.read(themeModeControllerProvider.notifier).bootstrap();

    expect(container.read(themeModeControllerProvider), AppThemeMode.dark);
  });

  test('falls back to system for invalid stored values', () async {
    final storage = MemoryThemeModeStorage(value: 'not-a-mode');
    final container = _container(storage);
    addTearDown(container.dispose);

    await container.read(themeModeControllerProvider.notifier).bootstrap();

    expect(container.read(themeModeControllerProvider), AppThemeMode.system);
  });

  test('falls back to system when storage read fails', () async {
    final storage = MemoryThemeModeStorage(readError: Exception('locked'));
    final container = _container(storage);
    addTearDown(container.dispose);

    await container.read(themeModeControllerProvider.notifier).bootstrap();

    expect(container.read(themeModeControllerProvider), AppThemeMode.system);
  });

  test('persists theme mode changes', () async {
    final storage = MemoryThemeModeStorage();
    final container = _container(storage);
    addTearDown(container.dispose);

    await container
        .read(themeModeControllerProvider.notifier)
        .setThemeMode(AppThemeMode.dark);

    expect(container.read(themeModeControllerProvider), AppThemeMode.dark);
    expect(storage.value, 'dark');
  });

  test('keeps the selected mode when storage write fails', () async {
    final storage = MemoryThemeModeStorage(writeError: Exception('locked'));
    final container = _container(storage);
    addTearDown(container.dispose);

    await container
        .read(themeModeControllerProvider.notifier)
        .setThemeMode(AppThemeMode.light);

    expect(container.read(themeModeControllerProvider), AppThemeMode.light);
    expect(storage.value, isNull);
  });
}

class MemoryThemeModeStorage implements OpenCloudThemeModeStorage {
  MemoryThemeModeStorage({this.value, this.readError, this.writeError});

  String? value;
  Object? readError;
  Object? writeError;

  @override
  Future<String?> readThemeMode() async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return value;
  }

  @override
  Future<void> writeThemeMode(String value) async {
    final error = writeError;
    if (error != null) {
      throw error;
    }
    this.value = value;
  }
}

ProviderContainer _container(MemoryThemeModeStorage storage) {
  return ProviderContainer(
    overrides: [themeModeStorageProvider.overrideWithValue(storage)],
  );
}
