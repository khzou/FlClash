import 'dart:io';

import 'package:fl_clash/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app_localizations.dart';
import 'constant.dart';
import 'print.dart';
import 'system.dart';
import 'window.dart';

class Tray {
  static Tray? _instance;

  bool _isInitialized = false;
  String _lastTrayIconPath = '';
  String _lastToolTip = '';
  String _lastTrayTitle = '';
  String _lastMenuSignature = '';

  Tray._internal();

  factory Tray() {
    _instance ??= Tray._internal();
    return _instance!;
  }

  String get trayIconSuffix {
    return system.isWindows ? 'ico' : 'png';
  }

  Future<void> destroy() async {
    await trayManager.destroy();
    _isInitialized = false;
    _lastTrayIconPath = '';
    _lastToolTip = '';
    _lastTrayTitle = '';
    _lastMenuSignature = '';
  }

  String getTryIcon({required bool isStart, required bool tunEnable}) {
    if (system.isMacOS || !isStart) {
      return 'assets/images/icon/status_1.$trayIconSuffix';
    }
    if (!tunEnable) {
      return 'assets/images/icon/status_2.$trayIconSuffix';
    }
    return 'assets/images/icon/status_3.$trayIconSuffix';
  }

  Future<void> _updateSystemTray({
    required bool isStart,
    required bool tunEnable,
  }) async {
    final nextIconPath = getTryIcon(isStart: isStart, tunEnable: tunEnable);
    if (_lastTrayIconPath != nextIconPath) {
      await trayManager.setIcon(nextIconPath, isTemplate: true);
      _lastTrayIconPath = nextIconPath;
    }
    if (!Platform.isLinux && _lastToolTip != appName) {
      await trayManager.setToolTip(appName);
      _lastToolTip = appName;
    }
  }

  Future<void> ensureInitialized({
    required TrayState trayState,
    required Traffic traffic,
  }) async {
    if (_isInitialized) {
      return;
    }
    await updateVisuals(trayState: trayState, traffic: traffic, force: true);
    await _updateMenu(trayState);
    _isInitialized = true;
  }

  Future<void> updateVisuals({
    required TrayState trayState,
    required Traffic traffic,
    bool force = false,
  }) async {
    await _updateSystemTray(
      isStart: trayState.isStart,
      tunEnable: trayState.tunEnable,
    );
    if (!system.isMacOS) {
      return;
    }
    final title = trayState.isStart && trayState.showTrayTitle
        ? traffic.trayTitle
        : '';
    await _setTrayTitle(title, force: force);
  }

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
  }) async {
    await ensureInitialized(trayState: trayState, traffic: traffic);
    await updateVisuals(trayState: trayState, traffic: traffic, force: true);
    await _updateMenu(trayState);
  }

  Future<void> _updateMenu(TrayState trayState) async {
    if (system.isAndroid) {
      return;
    }
    final menuSignature = _buildMenuSignature(trayState);
    if (_lastMenuSignature == menuSignature) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    List<MenuItem> menuItems = [];
    final showMenuItem = MenuItem(
      label: appLocalizations.show,
      onClick: (_) {
        window?.show();
      },
    );
    menuItems.add(showMenuItem);
    final startMenuItem = MenuItem.checkbox(
      label: trayState.isStart ? appLocalizations.stop : appLocalizations.start,
      onClick: (_) async {
        appController.updateStart();
      },
      checked: false,
    );
    menuItems.add(startMenuItem);
    if (system.isMacOS) {
      final speedStatistics = MenuItem.checkbox(
        label: appLocalizations.speedStatistics,
        onClick: (_) async {
          appController.updateSpeedStatistics();
        },
        checked: trayState.showTrayTitle,
      );
      menuItems.add(speedStatistics);
    }
    menuItems.add(MenuItem.separator());
    for (final mode in Mode.values) {
      menuItems.add(
        MenuItem.checkbox(
          label: Intl.message(mode.name),
          onClick: (_) {
            appController.changeMode(mode);
          },
          checked: mode == trayState.mode,
        ),
      );
    }
    menuItems.add(MenuItem.separator());
    if (system.isMacOS) {
      for (final group in trayState.groups) {
        List<MenuItem> subMenuItems = [];
        final selectedProxyName = appController.getSelectedProxyName(
          group.name,
        );
        for (final proxy in group.all) {
          subMenuItems.add(
            MenuItem.checkbox(
              label: proxy.name,
              checked: selectedProxyName == proxy.name,
              onClick: (_) {
                appController.updateCurrentSelectedMap(group.name, proxy.name);
                appController.changeProxy(
                  groupName: group.name,
                  proxyName: proxy.name,
                );
              },
            ),
          );
        }
        menuItems.add(
          MenuItem.submenu(
            label: group.name,
            submenu: Menu(items: subMenuItems),
          ),
        );
      }
      if (trayState.groups.isNotEmpty) {
        menuItems.add(MenuItem.separator());
      }
    }
    if (trayState.isStart) {
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.tun,
          onClick: (_) {
            appController.updateTun();
          },
          checked: trayState.tunEnable,
        ),
      );
      menuItems.add(
        MenuItem.checkbox(
          label: appLocalizations.systemProxy,
          onClick: (_) {
            appController.updateSystemProxy();
          },
          checked: trayState.systemProxy,
        ),
      );
      menuItems.add(MenuItem.separator());
    }
    final autoStartMenuItem = MenuItem.checkbox(
      label: appLocalizations.autoLaunch,
      onClick: (_) async {
        appController.updateAutoLaunch();
      },
      checked: trayState.autoLaunch,
    );
    final copyEnvVarMenuItem = MenuItem(
      label: appLocalizations.copyEnvVar,
      onClick: (_) async {
        await _copyEnv(trayState.port);
      },
    );
    menuItems.add(autoStartMenuItem);
    menuItems.add(copyEnvVarMenuItem);
    menuItems.add(MenuItem.separator());
    final exitMenuItem = MenuItem(
      label: appLocalizations.exit,
      onClick: (_) async {
        await appController.handleExit();
      },
    );
    menuItems.add(exitMenuItem);
    final menu = Menu(items: menuItems);
    await trayManager.setContextMenu(menu);
    _lastMenuSignature = menuSignature;
    stopwatch.stop();
    commonPrint.log(
      '[TRAY] menu rebuild took ${stopwatch.elapsedMilliseconds}ms, ${menuItems.length} items',
    );
  }

  Future<void> updateTrayTitle(String title) async {
    if (!system.isMacOS) {
      return;
    }
    await _setTrayTitle(title);
  }

  Future<void> _setTrayTitle(String title, {bool force = false}) async {
    if (!force && _lastTrayTitle == title) {
      return;
    }
    await trayManager.setTitle(title);
    _lastTrayTitle = title;
  }

  String _buildMenuSignature(TrayState trayState) {
    final buffer = StringBuffer()
      ..write(trayState.mode.name)
      ..write('|${trayState.port}')
      ..write('|${trayState.autoLaunch}')
      ..write('|${trayState.systemProxy}')
      ..write('|${trayState.tunEnable}')
      ..write('|${trayState.isStart}')
      ..write('|${trayState.locale}')
      ..write('|${trayState.showTrayTitle}');
    for (final group in trayState.groups) {
      buffer.write('|g:${group.name}');
      buffer.write(':${trayState.selectedMap[group.name] ?? ''}');
      for (final proxy in group.all) {
        buffer.write(':${proxy.name}');
      }
    }
    return buffer.toString();
  }

  Future<void> _copyEnv(int port) async {
    final url = 'http://127.0.0.1:$port';

    final cmdline = system.isWindows
        ? 'set \$env:all_proxy=$url'
        : 'export all_proxy=$url';

    await Clipboard.setData(ClipboardData(text: cmdline));
  }
}

final tray = system.isDesktop ? Tray() : null;
