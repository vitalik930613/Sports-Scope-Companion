import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

/// Les huit sons qu'un jalon peut jouer — catalogue fermé, miroir exact de
/// `TrainingProgram::SOUNDS` côté Rails. La plupart sont ceux déjà embarqués
/// pour le radar, les cols et les klaxons ; `end2`/`end3` n'existent que pour
/// un programme d'entraînement (variantes de fin de tronçon), mais suivent le
/// même catalogue fermé plutôt qu'une liste à part.
enum WorkoutSound {
  start('start'),
  end('end'),
  end2('end2'),
  end3('end3'),
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

/// Les dix icônes qu'un jalon peut porter — catalogue fermé, miroir exact de
/// `TrainingProgram::ICONS` côté Rails et de `MILESTONE_ICONS`
/// (`trainingProgramStore.ts`). Purement descriptif ici : le dessin réel
/// (quelle icône FontAwesome pour quelle clé) vit dans `companion_icons.dart`,
/// pas dans ce fichier qui n'importe volontairement aucun paquet d'UI.
enum WorkoutMilestoneIcon {
  warmup('warmup'),
  sprint('sprint'),
  effort('effort'),
  recovery('recovery'),
  climb('climb'),
  cooldown('cooldown'),
  interval('interval'),
  hydration('hydration'),
  alert('alert'),
  finish('finish');

  const WorkoutMilestoneIcon(this.key);

  final String key;

  static WorkoutMilestoneIcon? parse(Object? raw) {
    if (raw is! String) return null;
    for (final icon in WorkoutMilestoneIcon.values) {
      if (icon.key == raw) return icon;
    }
    return null;
  }
}

/// Le moment où joue le son d'un jalon — catalogue fermé, miroir de
/// `TrainingProgram::CUE_TIMINGS` (`training_program.rb`).
enum WorkoutCueTiming {
  /// Décalé en avance pour se **terminer** au départ du jalon
  /// ([WorkoutCuePolicy]) — comportement par défaut, y compris quand le
  /// document ne porte pas la clé (site plus ancien que ce réglage).
  before('before'),

  /// Pile au franchissement, sans anticipation — ancien comportement,
  /// choisi jalon par jalon pour un simple repère qui n'a rien à annoncer
  /// à l'avance.
  at('at');

  const WorkoutCueTiming(this.key);

  final String key;

  /// [before] sur toute valeur absente ou inconnue — jamais [at] par défaut,
  /// qui désactiverait silencieusement l'anticipation sur un document plus
  /// ancien que ce réglage.
  static WorkoutCueTiming parse(Object? raw) {
    if (raw is String) {
      for (final timing in WorkoutCueTiming.values) {
        if (timing.key == raw) return timing;
      }
    }
    return WorkoutCueTiming.before;
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
    required this.icon,
    required this.cueTiming,
    required this.color,
    required this.textColor,
  });

  final int offsetSeconds;
  final WorkoutSound? sound;
  final String segmentName;

  /// L'icône du tronçon qu'ouvre ce jalon — voir `workoutMilestoneIconFor`
  /// (`companion_icons.dart`) pour le dessin réel.
  final WorkoutMilestoneIcon? icon;

  /// Voir [WorkoutCueTiming] — ne concerne que [WorkoutCuePolicy], sans effet
  /// sur le franchissement lui-même ([WorkoutPolicy]).
  final WorkoutCueTiming cueTiming;

  /// Fond/texte du tronçon, réglés dans l'éditeur — mêmes `#rrggbb` que
  /// `DashboardBlock.color`/`textColor`, mais propres au jalon : c'est ce que
  /// lisent `WorkoutSegmentCard`/`WorkoutRemainingCard` en repli quand le bloc
  /// lui-même ne fixe pas sa propre couleur.
  final Color? color;
  final Color? textColor;

  static WorkoutMilestone? parse(Object? raw) {
    if (raw is! Map) return null;
    final offset = raw['offset_seconds'];
    if (offset is! num || offset < 0) return null;
    return WorkoutMilestone(
      offsetSeconds: offset.toInt(),
      sound: WorkoutSound.parse(raw['sound']),
      segmentName: raw['segment_name'] is String ? raw['segment_name'] as String : '',
      icon: WorkoutMilestoneIcon.parse(raw['icon']),
      cueTiming: WorkoutCueTiming.parse(raw['cue_timing']),
      color: _colorOf(raw['color']),
      textColor: _colorOf(raw['text_color']),
    );
  }

  /// `#rrggbb` uniquement — même format que `sanitize_hex_color` côté site,
  /// mais l'appli ne lui fait pas confiance pour autant (même garde que
  /// `DashboardBlock._colorOf`, `dashboard_block.dart`).
  static Color? _colorOf(Object? raw) {
    if (raw is! String) return null;
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(raw);
    if (match == null) return null;
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
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

  /// Le tronçon en cours à [elapsed] — le dernier jalon dont l'offset est déjà
  /// atteint. Jamais `null` en pratique (le premier jalon est toujours à 0,
  /// garanti par [parse]) : signature nullable seulement pour un [elapsed]
  /// négatif, qu'aucun appelant ne produit.
  ///
  /// Pure et sans curseur, contrairement à `WorkoutPolicy.read` (qui ne rend
  /// un jalon franchi qu'une fois, au tic où il l'est) — c'est ce qu'il faut
  /// pour une case de tableau de bord, qui redemande le tronçon courant à
  /// chaque rebuild plutôt qu'une seule fois au passage.
  WorkoutMilestone? milestoneAt(Duration elapsed) {
    WorkoutMilestone? current;
    for (final milestone in milestones) {
      if (milestone.offsetSeconds > elapsed.inSeconds) break;
      current = milestone;
    }
    return current;
  }

  /// Le temps avant le prochain jalon, `null` une fois le dernier dépassé
  /// (programme terminé) — même caractère pur que [milestoneAt].
  Duration? remainingAt(Duration elapsed) {
    for (final milestone in milestones) {
      if (milestone.offsetSeconds > elapsed.inSeconds) {
        return Duration(seconds: milestone.offsetSeconds - elapsed.inSeconds);
      }
    }
    return null;
  }

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
