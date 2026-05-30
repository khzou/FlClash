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
    int effectiveDownloadSpeed(TrackerInfo connection) {
      return connection.downloadSpeed ?? connection.download;
    }

    int effectiveUploadSpeed(TrackerInfo connection) {
      return connection.uploadSpeed ?? connection.upload;
    }

    bool isDirectConnection(TrackerInfo connection) {
      final directChains = connection.chains.any(
        (chain) => chain.trim().toUpperCase() == 'DIRECT',
      );
      final directRule = connection.rule.trim().toUpperCase() == 'DIRECT';
      final directPayload =
          connection.rulePayload.trim().toUpperCase() == 'DIRECT';
      return directChains || directRule || directPayload;
    }

    int compareConnections(TrackerInfo a, TrackerInfo b) {
      final downloadCompare = effectiveDownloadSpeed(
        b,
      ).compareTo(effectiveDownloadSpeed(a));
      if (downloadCompare != 0) {
        return downloadCompare;
      }
      return effectiveUploadSpeed(b).compareTo(effectiveUploadSpeed(a));
    }

    final activeConnections = connections.where((connection) {
      final downloadSpeed = effectiveDownloadSpeed(connection);
      final uploadSpeed = effectiveUploadSpeed(connection);
      return downloadSpeed > 0 || uploadSpeed > 0;
    }).toList();

    final nonDirectConnections =
        activeConnections
            .where((connection) => !isDirectConnection(connection))
            .toList()
          ..sort(compareConnections);
    final directConnections =
        activeConnections.where(isDirectConnection).toList()
          ..sort(compareConnections);

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

    void writeGroup(String title, List<TrackerInfo> items) {
      if (items.isEmpty) {
        return;
      }
      buffer
        ..writeln(title)
        ..writeln('----------------------------------------');

      for (final connection in items) {
        final site = connection.metadata.host.isNotEmpty
            ? connection.metadata.host
            : connection.desc;
        final rule = connection.rulePayload.isNotEmpty
            ? '${connection.rule} (${connection.rulePayload})'
            : connection.rule;
        final tags = connection.chains.join(' > ');
        buffer
          ..writeln(site.isNotEmpty ? site : connection.desc)
          ..writeln(
            '  Down: ${effectiveDownloadSpeed(connection).traffic.show}/s  Up: ${effectiveUploadSpeed(connection).traffic.show}/s',
          )
          ..writeln('  Rule: $rule')
          ..writeln('  Tags: ${tags.isNotEmpty ? tags : "-"}')
          ..writeln();
      }
    }

    writeGroup('Non-Direct', nonDirectConnections);
    if (nonDirectConnections.isNotEmpty && directConnections.isNotEmpty) {
      buffer.writeln('========================================');
    }
    writeGroup('Direct', directConnections);

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
