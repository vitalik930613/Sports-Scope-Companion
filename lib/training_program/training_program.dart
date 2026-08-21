import 'package:flutter/foundation.dart';

/// Les six sons qu'un jalon peut jouer — catalogue fermé, miroir exact de
/// `TrainingProgram::SOUNDS` côté Rails et des fichiers `assets/sounds/*.wav`
/// déjà embarqués pour le radar, les cols et les klaxons. Aucun nouveau
/// fichier audio : un programme d'entraînement ne fait que réutiliser ceux
/// que l'appli sait déjà jouer.
enum WorkoutSound {
  start('start'),
  end('end'),
  bell('bell'),
  horn('horn'),
  horn2('horn2'),
  booster('booster');

  const WorkoutSound(this.key);

  final String key;

  String get asset => 'sounds/$key.wav';

  static WorkoutSound? parse(Object? raw) {
    if (raw is! String) return null;
    for (final sound in WorkoutSound.values) {
      if (sound.key == raw) return sound;
    }
    return null;
  }
}

/// Un jalon de la timeline : à [offsetSeconds] de l'activation du programme,
/// il ferme le tronçon en cours et en ouvre un nouveau nommé [segmentName],
/// en jouant [sound] si renseigné (le premier jalon, à 0, n'en joue
/// généralement aucun — rien à annoncer, le programme vient de démarrer).
@immutable
class WorkoutMilestone {
  const WorkoutMilestone({
    required this.offsetSeconds,
    required this.sound,
    required this.segmentName,
  });

  final int offsetSeconds;
  final WorkoutSound? sound;
  final String segmentName;

  static WorkoutMilestone? parse(Object? raw) {
    if (raw is! Map) return null;
    final offset = raw['offset_seconds'];
    if (offset is! num || offset < 0) return null;
    return WorkoutMilestone(
      offsetSeconds: offset.toInt(),
      sound: WorkoutSound.parse(raw['sound']),
      segmentName: raw['segment_name'] is String ? raw['segment_name'] as String : '',
    );
  }
}

/// Un programme d'entraînement du site, réduit à ce qu'il faut pour le
/// dérouler pendant une sortie.
///
/// Même principe que `RouteSummary` : le [shareToken] est la seule clé dont
/// l'appli a besoin, la navigation/le déroulement sont adressés par lui côté
/// Rails plutôt que par l'identifiant interne.
@immutable
class TrainingProgram {
  const TrainingProgram({
    required this.id,
    required this.name,
    required this.shareToken,
    required this.milestones,
  });

  final int id;
  final String name;
  final String shareToken;

  /// Triés par [WorkoutMilestone.offsetSeconds] croissant, premier élément
  /// toujours à 0 — garanti côté Rails (`TrainingProgram#validate_milestones`),
  /// revérifié ici au parse plutôt que supposé.
  final List<WorkoutMilestone> milestones;

  /// Décode `{ training_program: {...} }` ou l'objet programme directement.
  /// Défensif comme `RidePreset.parse` : jamais d'exception, `null` si le
  /// document est inexploitable (jalons manquants, mal triés, sans jalon à 0)
  /// — un programme à moitié compris ne doit jamais se dérouler à moitié.
  static TrainingProgram? parse(Object? raw) {
    try {
      final map = raw is Map && raw['training_program'] is Map
          ? raw['training_program'] as Map
          : raw;
      if (map is! Map) return null;

      final name = map['name'];
      final token = map['share_token'];
      if (name is! String || name.isEmpty) return null;
      if (token is! String || token.isEmpty) return null;

      final rawMilestones = map['milestones'];
      if (rawMilestones is! List || rawMilestones.isEmpty) return null;

      final milestones = [
        for (final entry in rawMilestones)
          if (WorkoutMilestone.parse(entry) case final m?) m,
      ];
      if (milestones.isEmpty || milestones.first.offsetSeconds != 0) return null;
      for (var i = 1; i < milestones.length; i++) {
        if (milestones[i].offsetSeconds <= milestones[i - 1].offsetSeconds) {
          return null;
        }
      }

      return TrainingProgram(
        id: map['id'] is num ? (map['id'] as num).toInt() : 0,
        name: name,
        shareToken: token,
        milestones: milestones,
      );
    } catch (e) {
      debugPrint('[entraînement] programme illisible : $e');
      return null;
    }
  }
}
