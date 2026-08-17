import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../battery_status.dart';
import 'block_card.dart';

/// L'état des batteries des capteurs BLE connus, posé dans une page de
/// données.
///
/// Contrairement au radar, **jamais coupé par le profil** — voir
/// `SensorSettings.allows(SensorKind.battery)` — donc pas de branche « coupé
/// par ce profil » ici : la seule chose qui varie est d'avoir ou non des
/// appareils connus, et d'avoir ou non lu leur pourcentage.
class BatteryBlockView extends StatelessWidget {
  const BatteryBlockView({
    super.key,
    required this.battery,
    this.mode = BatteryMode.list,
    this.color,
    this.textColor,
  });

  final ValueListenable<List<BatteryStatus>> battery;
  final BatteryMode mode;

  /// Fond réglé dans l'éditeur — voir [DashboardBlock.color].
  final Color? color;

  /// Texte réglé dans l'éditeur — voir [DashboardBlock.textColor]. N'affecte
  /// pas la couleur d'alerte d'une ligne sous le seuil, qui est une donnée et
  /// non la surface du texte (même règle que [StatRow.background]).
  final Color? textColor;

  static const _low = Color(0xFFEF5350); // même rouge que RadarBlockView._close

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<BatteryStatus>>(
      valueListenable: battery,
      builder: (context, devices, _) => switch (mode) {
        BatteryMode.list => _list(devices),
        BatteryMode.compact => _compact(devices),
      },
    );
  }

  Widget _list(List<BatteryStatus> devices) {
    if (devices.isEmpty) {
      return BlockCard(
        title: 'Batteries',
        lines: const ['Aucun capteur appairé.'],
        color: color,
        textColor: textColor,
      );
    }
    return StatCard(
      title: 'Batteries',
      icon: Icons.battery_full,
      color: color,
      textColor: textColor,
      rows: [
        for (final device in devices)
          StatRow(
            device.label,
            device.percent == null ? '—' : '${device.percent} %',
            icon: device.icon,
            background: device.low ? _low : null,
          ),
      ],
    );
  }

  /// Le pire pourcentage connu parmi les appareils qui en publient un — un
  /// seul chiffre, pour la case qui n'a pas la place d'en lister plusieurs.
  Widget _compact(List<BatteryStatus> devices) {
    if (devices.isEmpty) {
      return _emptyText('Aucun capteur appairé.', Colors.white38);
    }

    final known = [for (final d in devices) if (d.percent != null) d.percent!];
    if (known.isEmpty) return _emptyText('—', Colors.white38);

    final worst = known.reduce((a, b) => a < b ? a : b);
    final worstIsLow = devices.any((d) => d.percent == worst && d.low);
    return _emptyText('$worst %', worstIsLow ? _low : Colors.white);
  }

  Widget _emptyText(String label, Color ink) {
    return BlockSurface(
      background: color,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: ink,
          fontSize: 44,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
