import 'package:flutter/foundation.dart';

/// Une zone d'entraînement, en valeurs absolues (watts ou bpm).
///
/// Absolues et pas fractionnaires : le site a déjà fait le calcul avec le seuil
/// qu'il connaît, donc une zone affichée ici ne peut pas diverger de la sienne.
@immutable
class TrainingZone {
  const TrainingZone({required this.key, required this.lo, this.hi});

  /// `z1`…`z7` pour la puissance, `z1`…`z5` pour le cardio.
  final String key;

  final int lo;

  /// Borne haute exclue, nulle pour la dernière zone (ouverte vers le haut).
  final int? hi;

  bool contains(num value) => value >= lo && (hi == null || value < hi!);

  Map<String, dynamic> toJson() => {'key': key, 'lo': lo, 'hi': hi};

  static TrainingZone? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final lo = raw['lo'];
    if (key is! String || lo is! num) return null;
    return TrainingZone(
      key: key,
      lo: lo.toInt(),
      hi: raw['hi'] is num ? (raw['hi'] as num).toInt() : null,
    );
  }
}

/// Les seuils du cycliste, tels que le site les connaît.
///
/// Tout est facultatif : un compte sans capteur de puissance n'a pas de FTP, et
/// un compte tout neuf n'a rien du tout. Une zone n'est jamais fabriquée à partir
/// d'un seuil deviné — sans seuil, la liste est vide et l'écran le dit.
@immutable
class RiderProfile {
  const RiderProfile({
    this.ftpWatts,
    this.ftpSource,
    this.wPerKg,
    this.criticalPowerW,
    this.wPrimeJ,
    this.lthr,
    this.lthrSource,
    this.weightKg,
    this.powerZones = const [],
    this.hrZones = const [],
  });

  static const empty = RiderProfile();

  final int? ftpWatts;

  /// `manual` (test officiel saisi) ou `auto` (estimée depuis les sorties).
  final String? ftpSource;
  final double? wPerKg;

  /// Puissance critique (W) et capacité de travail anaérobie W′ (J), issues de
  /// l'ajustement du modèle CP sur la courbe puissance-durée côté site — pour
  /// le W′ balance affiché en roulant ([WPrimeBalance]). `null` quand la
  /// courbe est trop pauvre pour l'ajustement : l'appli retombe alors sur la
  /// FTP comme CP et une W′ par défaut.
  final int? criticalPowerW;
  final int? wPrimeJ;

  /// Seuil cardiaque (bpm) tel que le site l'utilise lui-même.
  final int? lthr;

  /// `manual` (test saisi sur le site) ou `auto` (estimé sur les courbes cardio des
  /// sorties, fenêtre glissante de 6 semaines). Même vocabulaire que [ftpSource].
  ///
  /// Le site a longtemps refusé d'envoyer un seuil cardiaque estimé, faute d'une
  /// estimation fiable au niveau de l'athlète : un compte sans saisie manuelle
  /// n'avait donc aucune zone cardio ici. Ce n'est plus le cas.
  final String? lthrSource;
  final double? weightKg;

  final List<TrainingZone> powerZones;
  final List<TrainingZone> hrZones;

  bool get hasPowerZones => powerZones.isNotEmpty;
  bool get hasHrZones => hrZones.isNotEmpty;

  /// La zone contenant cette puissance, `null` si on ne sait pas.
  TrainingZone? powerZoneFor(num watts) => _zoneFor(powerZones, watts);

  TrainingZone? hrZoneFor(num bpm) => _zoneFor(hrZones, bpm);

  static TrainingZone? _zoneFor(List<TrainingZone> zones, num value) {
    for (final zone in zones) {
      if (zone.contains(value)) return zone;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'ftp': {'watts': ftpWatts, 'source': ftpSource, 'w_per_kg': wPerKg},
        'cp': criticalPowerW,
        'w_prime': wPrimeJ,
        'lthr': lthr,
        'lthr_source': lthrSource,
        'weight_kg': weightKg,
        'power_zones': [for (final z in powerZones) z.toJson()],
        'hr_zones': [for (final z in hrZones) z.toJson()],
      };

  /// Décode la réponse de `/api/rider_profile`, telle que la page la relaie.
  /// Tolérant : un champ manquant vaut « inconnu », jamais une exception.
  static RiderProfile fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final ftp = raw['ftp'];

    return RiderProfile(
      ftpWatts: ftp is Map && ftp['watts'] is num
          ? (ftp['watts'] as num).toInt()
          : null,
      ftpSource: ftp is Map && ftp['source'] is String
          ? ftp['source'] as String
          : null,
      wPerKg: ftp is Map && ftp['w_per_kg'] is num
          ? (ftp['w_per_kg'] as num).toDouble()
          : null,
      criticalPowerW: raw['cp'] is num ? (raw['cp'] as num).toInt() : null,
      wPrimeJ: raw['w_prime'] is num ? (raw['w_prime'] as num).toInt() : null,
      lthr: raw['lthr'] is num ? (raw['lthr'] as num).toInt() : null,
      lthrSource: raw['lthr_source'] is String ? raw['lthr_source'] as String : null,
      weightKg:
          raw['weight_kg'] is num ? (raw['weight_kg'] as num).toDouble() : null,
      powerZones: _zones(raw['power_zones']),
      hrZones: _zones(raw['hr_zones']),
    );
  }

  static List<TrainingZone> _zones(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (TrainingZone.fromJson(entry) case final zone?) zone,
    ];
  }
}
