import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

class TrayManager extends ConsumerStatefulWidget {
  final Widget child;

  const TrayManager({super.key, required this.child});

  @override
  ConsumerState<TrayManager> createState() => _TrayContainerState();
}

class _TrayContainerState extends ConsumerState<TrayManager> with TrayListener {
  Timer? _hoverRefreshTimer;
  bool _hoverRefreshInFlight = false;

  Future<void> _syncTray() async {
    if (tray == null) {
      return;
    }
    await tray!.update(
      trayState: ref.read(trayStateProvider),
      traffic: ref.read(
        trafficsProvider.select((state) => state.list.safeLast(Traffic())),
      ),
    );
  }

  String _buildHoverText(List<TrackerInfo> connections, Traffic traffic) {
    final activeConnections =
        connections.where((connection) {
          final downloadSpeed = connection.downloadSpeed ?? 0;
          final uploadSpeed = connection.uploadSpeed ?? 0;
          return downloadSpeed > 0 || uploadSpeed > 0;
        }).toList()..sort((a, b) {
          final downloadCompare = (b.downloadSpeed ?? 0).compareTo(
            a.downloadSpeed ?? 0,
          );
          if (downloadCompare != 0) {
            return downloadCompare;
          }
          return (b.uploadSpeed ?? 0).compareTo(a.uploadSpeed ?? 0);
        });

    final buffer = StringBuffer()
      ..writeln('Speed')
      ..writeln('  Down: ${traffic.down.traffic.show}/s')
      ..writeln('  Up:   ${traffic.up.traffic.show}/s')
      ..writeln()
      ..writeln('Active Connections: ${activeConnections.length}')
      ..writeln();

    if (activeConnections.isEmpty) {
      buffer.write('No active connections');
      return buffer.toString();
    }

    for (final connection in activeConnections) {
      final site = connection.metadata.host.isNotEmpty
          ? connection.metadata.host
          : connection.metadata.destinationIP;
      final rule = connection.rulePayload.isNotEmpty
          ? '${connection.rule} (${connection.rulePayload})'
          : connection.rule;
      buffer
        ..writeln(site.isNotEmpty ? site : connection.desc)
        ..writeln(
          '  Down: ${(connection.downloadSpeed ?? 0).traffic.show}/s  Up: ${(connection.uploadSpeed ?? 0).traffic.show}/s',
        )
        ..writeln('  Rule: $rule')
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _refreshHoverText() async {
    if (tray == null || _hoverRefreshInFlight) {
      return;
    }
    _hoverRefreshInFlight = true;
    try {
      final connections = await coreController.getConnections();
      final traffic = ref.read(
        trafficsProvider.select((state) => state.list.safeLast(Traffic())),
      );
      await trayManager.setHoverText(_buildHoverText(connections, traffic));
    } finally {
      _hoverRefreshInFlight = false;
    }
  }

  void _startHoverRefresh() {
    _hoverRefreshTimer?.cancel();
    unawaited(_refreshHoverText());
    _hoverRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshHoverText());
    });
  }

  void _stopHoverRefresh() {
    _hoverRefreshTimer?.cancel();
    _hoverRefreshTimer = null;
    _hoverRefreshInFlight = false;
    unawaited(trayManager.setHoverText(''));
  }

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    unawaited(_syncTray());
    ref.listenManual(trayStateProvider, (prev, next) {
      if (prev != next) {
        unawaited(_syncTray());
      }
    });
    if (system.isMacOS) {
      ref.listenManual(displayedTrayTitleProvider, (prev, next) {
        if (prev != next) {
          if (tray != null) {
            unawaited(tray!.updateTrayTitle(next));
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(() async {
      await appController.updateTray();
      // ignore: deprecated_member_use
      await trayManager.popUpContextMenu(bringAppToFront: true);
    }());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    render?.active();
    super.onTrayMenuItemClick(menuItem);
  }

  @override
  void onTrayHoverEnter() {
    _startHoverRefresh();
  }

  @override
  void onTrayHoverExit() {
    _stopHoverRefresh();
  }

  @override
  onTrayIconMouseDown() {
    window?.show();
  }

  @override
  dispose() {
    _stopHoverRefresh();
    trayManager.removeListener(this);
    super.dispose();
  }
}
