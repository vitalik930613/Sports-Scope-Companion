import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../ui/zone_colors.dart';
import '../battery_status.dart';
import 'block_card.dart';

/// L'état des batteries des capteurs BLE connus, et de celle du téléphone lui-
/// même, posé dans une page de données.
///
/// Contrairement au radar, **jamais coupé par le profil** — voir
/// `SensorSettings.allows(SensorKind.battery)` — donc pas de branche « coupé
/// par ce profil » ici : la seule chose qui varie est d'avoir ou non des
/// appareils connus, et d'avoir ou non lu leur pourcentage. Même chose pour la
/// batterie du téléphone : elle n'a pas de réglage pour la couper, elle est
/// de toute façon toujours à portée de qui tient l'appareil en main.
class BatteryBlockView extends StatelessWidget {
  const BatteryBlockView({
    super.key,
    required this.battery,
    this.mode = BatteryMode.list,
    this.sensor,
    this.color,
    this.textColor,
  });

  final ValueListenable<List<BatteryStatus>> battery;
  final BatteryMode mode;

  /// Voir `BatteryBlock.sensor` — ne restreint que [_compact], la liste
  /// affiche déjà tous les appareils connus.
  final BatterySensor? sensor;

  /// Fond réglé dans l'éditeur — voir [DashboardBlock.color].
  final Color? color;

  /// Texte réglé dans l'éditeur — voir [DashboardBlock.textColor]. N'affecte
  /// pas la couleur d'alerte d'une ligne sous le seuil, qui est une donnée et
  /// non la surface du texte (même règle que [StatRow.background]).
  final Color? textColor;

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
            background:
                device.percent == null ? null : batteryLevelColor(device.percent!),
            // Grisée plutôt qu'effacée : la dernière lecture reste affichée
            // (un capteur débranché n'efface pas ce qu'il a mesuré, même
            // règle que `SensorHub.latest*`), mais ce n'est plus du direct.
            dimmed: !device.connected,
          ),
      ],
    );
  }

  /// Le pire pourcentage connu parmi les appareils qui en publient un — un
  /// seul chiffre, pour la case qui n'a pas la place d'en lister plusieurs.
  /// [sensor] restreint ce « parmi » à un seul appareil (BLE ou le téléphone
  /// lui-même), sinon la ceinture cardio oubliée sur la table gagnerait
  /// contre le capteur de puissance qu'on veut réellement surveiller.
  ///
  /// L'icône de l'appareil concerné accompagne le chiffre — sans elle, un
  /// seul pourcentage nu ne dit pas s'il vient du capteur de puissance ou du
  /// téléphone dans la poche. Elle n'apparaît que si elle ne peut désigner
  /// qu'un seul appareil ([_sharedIcon]) : au repli « tous appareils
  /// confondus » (pas de [sensor] réglé), plusieurs capacités différentes
  /// dans le lot rendraient l'icône trompeuse plutôt qu'utile.
  Widget _compact(List<BatteryStatus> devices) {
    final target = sensor;
    final pool = switch (target) {
      null => devices,
      BatterySensor.phone => [for (final d in devices) if (d.isPhone) d],
      _ => [for (final d in devices) if (d.kinds.contains(target.sensorKind)) d],
    };

    if (pool.isEmpty) {
      return _emptyText('Aucun capteur appairé.');
    }

    final known = [for (final d in pool) if (d.percent != null) d];
    if (known.isEmpty) {
      return _emptyText('—', icon: _sharedIcon(pool));
    }

    final worst = known.reduce((a, b) => a.percent! < b.percent! ? a : b);
    final levelColor = batteryLevelColor(worst.percent!);
    return BlockSurface(
      background: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(worst.icon, size: 28, color: Colors.white70),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: levelColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${worst.percent} %',
              maxLines: 1,
              style: TextStyle(
                color: foregroundOf(levelColor),
                fontSize: 44,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// L'icône commune à tout le lot, `null` si elle varie — voir [_compact].
  static IconData? _sharedIcon(List<BatteryStatus> pool) {
    final icons = pool.map((d) => d.icon).toSet();
    return icons.length == 1 ? icons.first : null;
  }

  /// Pas de pourcentage à montrer — ni fond de zone ni icône colorée,
  /// seulement le gris discret des mesures absentes.
  Widget _emptyText(String label, {IconData? icon}) {
    const ink = Colors.white38;
    final text = Text(
      label,
      maxLines: 1,
      style: const TextStyle(
        color: ink,
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    );
    return BlockSurface(
      background: color,
      child: icon == null
          ? text
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28, color: ink.withValues(alpha: 0.7)),
                const SizedBox(height: 4),
                text,
              ],
            ),
    );
  }
}
