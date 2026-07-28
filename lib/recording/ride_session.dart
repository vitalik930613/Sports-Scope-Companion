/// Une sortie enregistrée : ce qu'on en sait sans relire les points.
///
/// Le fichier de points fait foi pour le détail ; ce résumé n'existe que pour
/// afficher une liste sans ouvrir onze mille lignes de JSON. Il est réécrit
/// pendant la sortie (toutes les [RideRecorder.metaPeriod]) pour qu'une batterie
/// vide laisse quand même une entrée lisible.
class RideSession {
  const RideSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.pointCount = 0,
    this.distanceM = 0,
    this.movingSeconds = 0,
  });

  /// Identifiant *et* nom de dossier : l'instant de départ en UTC, sans les
  /// caractères qu'un système de fichiers refuse (`2026-07-28T14-03-11Z`).
  final String id;

  final DateTime startedAt;

  /// Renseigné à l'arrêt volontaire. `null` signale une sortie interrompue
  /// (crash, batterie) : les points écrits jusque-là restent exportables, et
  /// l'UI le dit plutôt que de faire passer une sortie tronquée pour complète.
  final DateTime? endedAt;

  final int pointCount;
  final double distanceM;

  /// Secondes effectivement enregistrées, pauses exclues. C'est le
  /// `total_timer_time` du `.fit`, à distinguer du temps écoulé.
  final int movingSeconds;

  bool get isFinished => endedAt != null;

  Duration get elapsed =>
      (endedAt ?? startedAt.add(Duration(seconds: movingSeconds)))
          .difference(startedAt);

  Duration get moving => Duration(seconds: movingSeconds);

  /// Identifiant de dossier pour un départ donné.
  static String idFor(DateTime startedAt) {
    final iso = startedAt.toUtc().toIso8601String();
    // `2026-07-28T14:03:11.123Z` → `2026-07-28T14-03-11Z` : les deux-points
    // sont interdits sur les partitions FAT (carte SD, transfert PC), et les
    // millisecondes n'apportent rien à un dossier.
    return '${iso.substring(0, 19).replaceAll(':', '-')}Z';
  }

  RideSession copyWith({
    DateTime? endedAt,
    int? pointCount,
    double? distanceM,
    int? movingSeconds,
  }) {
    return RideSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      pointCount: pointCount ?? this.pointCount,
      distanceM: distanceM ?? this.distanceM,
      movingSeconds: movingSeconds ?? this.movingSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'pointCount': pointCount,
        'distanceM': distanceM,
        'movingSeconds': movingSeconds,
      };

  static RideSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final startedAt = json['startedAt'];
    if (id is! String || id.isEmpty || startedAt is! String) return null;
    final start = DateTime.tryParse(startedAt);
    if (start == null) return null;

    final endedAt = json['endedAt'];
    return RideSession(
      id: id,
      startedAt: start.toUtc(),
      endedAt: endedAt is String ? DateTime.tryParse(endedAt)?.toUtc() : null,
      pointCount: json['pointCount'] is num
          ? (json['pointCount'] as num).round()
          : 0,
      distanceM:
          json['distanceM'] is num ? (json['distanceM'] as num).toDouble() : 0,
      movingSeconds: json['movingSeconds'] is num
          ? (json['movingSeconds'] as num).round()
          : 0,
    );
  }

  @override
  String toString() => 'RideSession($id, ${distanceM.round()} m, '
      '$movingSeconds s, ${isFinished ? 'terminée' : 'interrompue'})';
}
