import 'package:flutter/foundation.dart';

/// Le budget de charge du jour, tel que le site le calcule.
///
/// Il répond à la question qu'on se pose au guidon et à laquelle aucun capteur ne
/// répond : **je continue ou je rentre ?** Le cardio dit l'effort de l'instant, la
/// puissance dit ce qu'on produit — mais ni l'un ni l'autre ne sait qu'on a déjà
/// encaissé 900 TSS cette semaine.
///
/// Tout est en **TSS** (Training Stress Score) : une heure à son seuil vaut 100.
/// C'est la seule unité du document, il n'y a donc rien à convertir.
///
/// **Calculé par le site et pas ici**, contrairement à tout le reste du tableau de
/// bord. Ce n'est pas un choix de commodité : la cible de la semaine, le schéma
/// d'affûtage et le plancher de fatigue toléré forment un morceau de logique qui
/// vit déjà sur la page Performances (`useTrainingPlan.ts`), avec l'historique
/// complet des sorties sous la main. En refaire une version ici donnerait deux
/// plafonds pour un athlète — et le second à se tromper serait celui qu'on lit en
/// roulant, c'est-à-dire celui sur lequel on décide.
///
/// Le chemin : la page de navigation le calcule et le pousse par le pont
/// (`companionBridge.ts`, message `training_budget`), la coquille le range dans
/// [TrainingBudgetStore], qui le garde sur disque pour les départs hors ligne.
///
/// **Rien ici ne lève.** Même convention que [RiderProfile] : un champ manquant
/// vaut « inconnu », jamais une exception. Le site peut être plus récent que
/// l'appli.
@immutable
class TrainingBudget {
  const TrainingBudget({
    required this.date,
    required this.day,
    required this.week,
    required this.form,
    required this.risk,
    this.days = const [],
  });

  /// Le jour pour lequel ce budget a été calculé.
  ///
  /// Pas décoratif : le budget est gardé sur disque pour les sorties qui partent
  /// sans réseau, et celui de la semaine dernière ne doit pas s'afficher comme
  /// celui du jour. C'est cette date qui permet de le dire.
  final DateTime date;

  final DayBudget day;
  final WeekBudget week;

  /// La fraîcheur (TSB) et sa zone : « productif », « surmené »…
  final RiderForm form;

  /// Le risque de blessure (ACWR) et sa zone.
  final InjuryRisk risk;

  /// Le plan jour par jour de la semaine en cours (lundi → dimanche), quand le
  /// site en a poussé un. Vide sur un budget plus ancien que ce champ — un site
  /// plus récent que l'appli est déjà le cas ordinaire, jamais une exception.
  final List<DayEstimate> days;

  /// Ce budget est-il celui de [now] ?
  bool isFor(DateTime now) =>
      date.year == now.year && date.month == now.month && date.day == now.day;

  static TrainingBudget? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final date = DateTime.tryParse(raw['date']?.toString() ?? '');
    // Sans date, on ne saurait pas dire si le budget est celui du jour — et un
    // budget qu'on ne peut pas dater ne peut pas être affiché honnêtement.
    if (date == null) return null;

    return TrainingBudget(
      date: date,
      day: DayBudget.fromJson(raw['day']),
      week: WeekBudget.fromJson(raw['week']),
      form: RiderForm.fromJson(raw['form']),
      risk: InjuryRisk.fromJson(raw['risk']),
      days: _days(raw['days']),
    );
  }

  Map<String, dynamic> toJson() => {
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'day': day.toJson(),
        'week': week.toJson(),
        'form': form.toJson(),
        'risk': risk.toJson(),
        'days': days.map((d) => d.toJson()).toList(),
      };
}

/// Un jour de la semaine en cours du plan de charge : ce qui est visé, ce qui est
/// fait. Distinct de [DayBudget] — celui-là ne décrit qu'aujourd'hui, avec le
/// plafond de fatigue en plus ; celui-ci décrit un jour quelconque de la semaine,
/// pour une vue d'ensemble plutôt qu'une décision « je continue ou je rentre ? ».
///
/// `target`/`done` sont individuellement nuls plutôt que zéro quand le site n'a
/// rien à en dire — un jour à venir n'a pas de `done`, un jour passé sans plan
/// reconstitué n'a pas de `target`. Confondre les deux avec zéro se lirait comme
/// « repos », qui est un conseil et pas une absence de donnée.
@immutable
class DayEstimate {
  const DayEstimate({required this.date, this.target, this.done});

  final DateTime date;
  final int? target;
  final int? done;

  static DayEstimate? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final date = DateTime.tryParse(raw['date']?.toString() ?? '');
    if (date == null) return null;

    return DayEstimate(
      date: date,
      target: raw['target'] is num ? (raw['target'] as num).round() : null,
      done: raw['done'] is num ? (raw['done'] as num).round() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'target': target,
        'done': done,
      };
}

/// Sept jours au plus : au-delà, ce n'est plus la semaine en cours que le site
/// décrirait.
List<DayEstimate> _days(Object? raw) {
  if (raw is! List) return const [];
  return raw.take(7).map(DayEstimate.fromJson).whereType<DayEstimate>().toList();
}

/// Ce que la journée autorise.
@immutable
class DayBudget {
  const DayBudget({this.done = 0, this.target = 0, this.max = 0});

  /// Le TSS **déjà enregistré** aujourd'hui, sortie en cours exclue : elle n'est
  /// téléversée nulle part, c'est le téléphone qui l'ajoute (cf. `rideTss`).
  final int done;

  /// Ce que la journée vise, une fois la cible de la semaine répartie et bornée
  /// par la fatigue. Zéro un jour de repos, et c'est une réponse.
  final int target;

  /// Le plafond : au-delà, la fraîcheur de demain passe sous le plancher que
  /// l'objectif d'entraînement tolère. Jamais sous [target] — le site s'en assure,
  /// une jauge dont la cible dépasse le maximum ne se dessine pas.
  final int max;

  static DayBudget fromJson(Object? raw) {
    if (raw is! Map) return const DayBudget();
    return DayBudget(
      done: _int(raw['done']),
      target: _int(raw['target']),
      max: _int(raw['max']),
    );
  }

  Map<String, dynamic> toJson() =>
      {'done': done, 'target': target, 'max': max};
}

/// Où en est la semaine, du lundi au dimanche.
@immutable
class WeekBudget {
  const WeekBudget({
    this.target = 0,
    this.done = 0,
    this.planned = 0,
    this.remaining = 0,
  });

  final int target;
  final int done;

  /// Le TSS des itinéraires déjà accrochés aux jours à venir.
  final int planned;

  /// Ce qu'il reste à **placer** : la cible, moins le fait, moins le prévu.
  final int remaining;

  static WeekBudget fromJson(Object? raw) {
    if (raw is! Map) return const WeekBudget();
    return WeekBudget(
      target: _int(raw['target']),
      done: _int(raw['done']),
      planned: _int(raw['planned']),
      remaining: _int(raw['remaining']),
    );
  }

  Map<String, dynamic> toJson() =>
      {'target': target, 'done': done, 'planned': planned, 'remaining': remaining};
}

/// La fraîcheur du jour (TSB = forme de fond − fatigue).
@immutable
class RiderForm {
  const RiderForm({this.ctl = 0, this.atl = 0, this.tsb = 0, this.zone});

  final int ctl;
  final int atl;
  final int tsb;

  /// `very_fresh`, `fresh`, `neutral`, `productive`, `overreaching`. `null` quand
  /// le site n'a rien su dire — on n'invente pas une couleur.
  final String? zone;

  static RiderForm fromJson(Object? raw) {
    if (raw is! Map) return const RiderForm();
    return RiderForm(
      ctl: _int(raw['ctl']),
      atl: _int(raw['atl']),
      tsb: _int(raw['tsb']),
      zone: raw['zone'] is String ? raw['zone'] as String : null,
    );
  }

  Map<String, dynamic> toJson() =>
      {'ctl': ctl, 'atl': atl, 'tsb': tsb, 'zone': zone};
}

/// Le ratio charge aiguë / chronique (ACWR) : la charge des 7 derniers jours
/// rapportée à celle des 28. Au-delà de 1,5, le risque de blessure grimpe.
@immutable
class InjuryRisk {
  const InjuryRisk({this.acwr, this.zone});

  /// `null` tant que l'historique n'atteint pas 28 jours : le ratio n'y voudrait
  /// rien dire, et l'appli affiche un tiret plutôt qu'un chiffre de démarrage.
  final double? acwr;

  /// `detraining`, `optimal`, `caution`, `high_risk`.
  final String? zone;

  static InjuryRisk fromJson(Object? raw) {
    if (raw is! Map) return const InjuryRisk();
    return InjuryRisk(
      acwr: raw['acwr'] is num ? (raw['acwr'] as num).toDouble() : null,
      zone: raw['zone'] is String ? raw['zone'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {'acwr': acwr, 'zone': zone};
}

int _int(Object? raw) => raw is num ? raw.round() : 0;
