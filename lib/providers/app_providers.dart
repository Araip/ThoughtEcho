import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../services/backup_service.dart';
import '../services/clipboard_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/feature_guide_service.dart';
import '../services/location_service.dart';
import '../services/mmkv_service.dart';
import '../services/note_sync_service.dart';
import '../services/settings_service.dart';
import '../services/unified_log_service.dart';
import '../services/weather_service.dart';
import '../services/webdav_sync_service.dart';
import '../theme/app_theme.dart';
import '../controllers/search_controller.dart';

/// 构建应用级别的所有 Provider
List<SingleChildWidget> buildAppProviders({
  required SettingsService settingsService,
  required DatabaseService databaseService,
  required LocationService locationService,
  required WeatherService weatherService,
  required ClipboardService clipboardService,
  required UnifiedLogService unifiedLogService,
  required AppTheme appTheme,
  required ConnectivityService connectivityService,
  required FeatureGuideService featureGuideService,
  required MMKVService mmkvService,
  required ValueNotifier<bool> servicesInitialized,
}) {
  return [
    ChangeNotifierProvider(create: (_) => settingsService),
    // 兼容性说明：DatabaseService现在有dispose方法，但Provider会自动处理
    ChangeNotifierProvider(create: (_) => databaseService),
    ChangeNotifierProvider(create: (_) => locationService),
    ChangeNotifierProvider(create: (_) => weatherService),
    ChangeNotifierProvider(create: (_) => clipboardService),
    ChangeNotifierProvider(create: (_) => unifiedLogService),
    ChangeNotifierProvider(create: (_) => appTheme),
    ChangeNotifierProvider(create: (_) => connectivityService),
    ChangeNotifierProvider(create: (_) => featureGuideService),
    ChangeNotifierProvider(create: (_) => NoteSearchController()),
    ChangeNotifierProvider(create: (_) => WebDAVSyncService()),
    Provider.value(value: mmkvService), // 使用 Provider.value 提供 MMKVService
    // 提供初始化状态的值（debug 下必须使用 ListenableProvider）
    ListenableProvider<ValueNotifier<bool>>.value(value: servicesInitialized),
    ValueListenableProvider<bool>.value(value: servicesInitialized),
    ProxyProvider2<DatabaseService, SettingsService, BackupService>(
      update: (context, dbService, settingsService, previous) => BackupService(
        databaseService: dbService,
        settingsService: settingsService,
      ),
    ),
    ChangeNotifierProxyProvider3<BackupService, DatabaseService, SettingsService,
        NoteSyncService>(
      create: (context) => NoteSyncService(
        backupService: context.read<BackupService>(),
        databaseService: context.read<DatabaseService>(),
        settingsService: context.read<SettingsService>(),
      ),
      update: (
        context,
        backupService,
        databaseService,
        settingsService,
        previous,
      ) =>
          previous ??
          NoteSyncService(
            backupService: backupService,
            databaseService: databaseService,
            settingsService: settingsService,
          ),
    ),
  ];
}
