import 'package:flutter/material.dart';

import '../../account/rider_profile_store.dart';
import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import '../../training/ride_load.dart';
import '../../training/training_budget.dart';
import '../../training/training_budget_store.dart';
import 'block_card.dart';

/// Le budget de charge : ce qu'il reste à faire aujourd'hui, et jusqu'où on peut
/// aller sans se cramer.
///
/// La seule carte du tableau de bord qui réponde à « **je continue ou je
/// rentre ?** ». Le cardio dit l'effort de l'instant, les moyennes disent la
/// sortie — aucun capteur ne sait qu'on a déjà encaissé 900 TSS cette semaine, ni
/// qu'un objectif est dans douze jours.
///
/// Trois choses s'y lisent, et l'ordre n'est pas décoratif :
///
///  1. **le chiffre** — « 62 / 85 » : ce qu'on a fait, ce qu'on visait ;
///  2. **la barre** — la même chose en longueur, avec le repère de la cible et le
///     plafond de fatigue au bout. C'est elle qu'on lit du coin de l'œil, parce
///     qu'une proportion se voit sans se déchiffrer ;
///  3. **le contexte** — la fraîcheur et le risque de blessure, deux pastilles de
///     couleur. Elles restent toujours dessinées, comme le reste de la carte —
///     [ScaleToFit] réduit l'ensemble plutôt que de les retirer.
///
/// Le TSS de la sortie en cours **n'est pas dans le budget** : le site ne l'a pas,
/// elle ne sera téléversée qu'une fois rentré. Il est calculé ici, avec la même
/// cascade que le site (cf. [rideTss]), et ajouté à ce qui est déjà enregistré.
class TrainingBudgetCard extends StatelessWidget {
  const TrainingBudgetCard({
    super.key,
    required this.budgets,
    required this.recorder,
    required this.riderProfile,
    this.mode = TrainingBudgetMode.day,
    this.now,
  });

  final TrainingBudgetStore budgets;
  final RideRecorder recorder;

  /// Les seuils, d'où sort le TSS de la sortie en cours. Sans FTP ni seuil
  /// cardiaque, on retombe sur l'intensité par défaut du vélo — comme le site.
  final RiderProfileStore riderProfile;

  final TrainingBudgetMode mode;

  /// Le jour courant, pour dater le budget. Injectable pour les tests : un
  /// composant qui lit l'horloge ne se teste que le bon jour.
  final DateTime? now;

  static const _title = 'Budget de charge';

  @override
  Widget build(BuildContext context) {
    // Écoute les trois : le budget arrive du site en cours de sortie, les
    // statistiques grossissent à chaque point capturé, et les seuils peuvent
    // arriver après le départ.
    return ListenableBuilder(
      listenable: Listenable.merge([budgets, recorder, riderProfile]),
      builder: (context, _) {
        final budget = budgets.budget;

        // Deux façons de n'avoir rien à dire, et pas le même message : sans
        // budget, c'est le site qu'il faut atteindre — pas un capteur à
        // connecter. La phrase nomme donc ce qu'on attend et d'où ça vient.
        if (budget == null) {
          return const BlockCard(
            title: _title,
            lines: [
              'Le budget arrive avec la page de navigation, une fois connecté au site.',
            ],
          );
        }

        final today = now ?? DateTime.now();
        return BlockSurface(child: _content(budget, today));
      },
    );
  }

  /// La largeur à laquelle la carte se construit avant mise à l'échelle.
  /// Fixe et non celle de la case — [ScaleToFit] la ramène à la case réelle.
  static const _naturalWidth = 240.0;

  Widget _content(TrainingBudget budget, DateTime today) {
    final view = mode == TrainingBudgetMode.week
        ? _weekView(budget)
        : _dayView(budget);

    const metrics = BlockMetrics.natural;

    return SizedBox(
      width: _naturalWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _titleFor(budget, today),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: metrics.titleSize,
            ),
          ),
          SizedBox(height: metrics.gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Le chiffre rapetisse plutôt que d'être tronqué : « 124 / 1… » ne
              // vaut pas mieux que rien, alors qu'un chiffre plus petit se lit
              // encore, s'il ne tient pas à côté du plafond dans la largeur
              // naturelle de la carte.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    view.figure,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.budgetFigureSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              SizedBox(width: metrics.gap),
              Text(
                view.aside,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: metrics.unitSize,
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.gap),
          _BudgetBar(view: view, height: metrics.barHeight),
          SizedBox(height: metrics.gap),
          _context(budget),
        ],
      ),
    );
  }

  /// Le titre dit la date **dès qu'elle n'est plus celle du jour**.
  ///
  /// Un budget vieux d'un jour n'est pas faux — la forme de fond ne bouge pas en
  /// une nuit — mais son « déjà fait » l'est : c'est celui d'hier. Une sortie
  /// partie sans réseau affiche donc son budget en le datant, plutôt que de le
  /// faire passer pour celui d'aujourd'hui.
  String _titleFor(TrainingBudget budget, DateTime today) {
    final scope = mode == TrainingBudgetMode.week ? 'La semaine' : 'Aujourd\'hui';
    if (budget.isFor(today)) return scope;

    return '$scope · au ${budget.date.day}/${budget.date.month}';
  }

  /// Le mode « aujourd'hui ». L'échelle de la barre est le plafond de fatigue :
  /// c'est ce qui donne son sens au repère de la cible, posé quelque part avant
  /// la fin. Une sortie qui dépasse le plafond étire l'échelle plutôt que de
  /// sortir de la case — on doit voir de combien on l'a dépassé.
  _BudgetView _dayView(TrainingBudget budget) {
    final ride = recorder.isActive
        ? (rideTss(recorder.stats, riderProfile.profile)?.tss ?? 0)
        : 0.0;
    final done = budget.day.done.toDouble();
    final total = done + ride;

    return _BudgetView(
      figure: '${total.round()} / ${budget.day.target}',
      aside: 'max ${budget.day.max}',
      scale: [budget.day.max.toDouble(), total, 1.0].reduce((a, b) => a > b ? a : b),
      done: done,
      live: ride,
      // Au-delà de la cible, la sortie n'est plus « en route vers » mais
      // « au-delà de » : la barre change de couleur là où le conseil change de
      // sens. Au-delà du plafond, elle passe au rouge — c'est le moment où le
      // composant a quelque chose à dire.
      liveColor: total > budget.day.max
          ? _overColor
          : (total > budget.day.target ? _aheadColor : _doneColor),
      mark: budget.day.target.toDouble(),
    );
  }

  /// Le mode « la semaine ». Le prévu (les itinéraires déjà accrochés aux jours à
  /// venir) prolonge le fait, en orange : ce n'est pas encore de la charge, mais
  /// c'est déjà de la charge décidée.
  _BudgetView _weekView(TrainingBudget budget) {
    final done = budget.week.done.toDouble();
    final planned = budget.week.planned.toDouble();

    return _BudgetView(
      figure: '${budget.week.done} / ${budget.week.target}',
      aside: 'reste ${budget.week.remaining}',
      scale: [budget.week.target.toDouble(), done + planned, 1.0]
          .reduce((a, b) => a > b ? a : b),
      done: done,
      live: planned,
      liveColor: _aheadColor,
      mark: budget.week.target.toDouble(),
    );
  }

  /// Les pastilles. Elles rapetissent plutôt que de déborder — dans la largeur
  /// naturelle de la carte, une police système plus grande vaut mieux en plus
  /// petit qu'amputée d'un des deux chiffres ; le reste vient de la mise à
  /// l'échelle globale de [ScaleToFit].
  Widget _context(TrainingBudget budget) {
    const metrics = BlockMetrics.natural;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: mode == TrainingBudgetMode.week
            ? [
                _Chip(
                  icon: Icons.event_available,
                  color: _aheadColor,
                  label: '${budget.week.planned} prévus',
                ),
              ]
            : [
                _Chip(
                  icon: Icons.battery_charging_full,
                  color: _formColors[budget.form.zone],
                  label: _signed(budget.form.tsb),
                ),
                SizedBox(width: metrics.gap),
                _Chip(
                  icon: Icons.warning_amber_rounded,
                  color: _riskColors[budget.risk.zone],
                  // Le tiret et pas un chiffre quand l'ACWR manque : il faut
                  // 28 jours d'historique pour qu'il veuille dire quelque chose,
                  // et un ratio de démarrage se lirait comme un verdict.
                  label:
                      budget.risk.acwr?.toStringAsFixed(2).replaceAll('.', ',') ??
                          '—',
                ),
              ],
      ),
    );
  }

  static String _signed(int value) => value > 0 ? '+$value' : '$value';
}

/// Ce qu'il y a à dessiner, une fois le mode choisi. Les deux modes se ramènent à
/// la même figure : un chiffre, une barre en deux segments, un repère.
@immutable
class _BudgetView {
  const _BudgetView({
    required this.figure,
    required this.aside,
    required this.scale,
    required this.done,
    required this.live,
    required this.liveColor,
    required this.mark,
  });

  final String figure;
  final String aside;

  /// Le fond d'échelle de la barre. Jamais zéro : une division par zéro ne se
  /// dessine pas.
  final double scale;

  /// Ce qui est déjà enregistré (aujourd'hui, ou depuis lundi).
  final double done;

  /// Ce qui s'y ajoute et qui bouge : la sortie en cours, ou le prévu de la
  /// semaine. C'est le segment qu'on regarde.
  final double live;

  final Color liveColor;

  /// La cible, en TSS. Un trait blanc sur la barre.
  final double mark;
}

/// La barre : le fait, puis ce qui bouge, puis le repère de la cible par-dessus.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.view, required this.height});

  final _BudgetView view;
  final double height;

  @override
  Widget build(BuildContext context) {
    final done = (view.done / view.scale).clamp(0.0, 1.0);
    final live = (view.live / view.scale).clamp(0.0, 1.0 - done);
    final mark = (view.mark / view.scale).clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: _trackColor)),
                Row(
                  children: [
                    // Le déjà-enregistré est le même vert que la sortie en cours,
                    // en sourdine : c'est la même charge, mais ce n'est pas celle
                    // qu'on est en train de produire.
                    SizedBox(
                      width: width * done,
                      child: const ColoredBox(color: _doneDimColor),
                    ),
                    SizedBox(
                      width: width * live,
                      child: ColoredBox(color: view.liveColor),
                    ),
                  ],
                ),
                // Le repère de la cible, **par-dessus** les segments : il doit se
                // voir aussi bien quand on en est loin que quand on l'a dépassé.
                Positioned(
                  left: (width * mark - 1).clamp(0.0, width - 2),
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: const ColoredBox(color: Colors.white),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Une pastille de contexte : une icône, une couleur, un chiffre.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.color,
    required this.label,
    required this.icon,
  });

  /// `null` quand le site n'a pas su classer la zone : la pastille reste grise,
  /// ce qui ne dit rien — et c'est exactement l'information.
  final Color? color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: metrics.iconSize, color: Colors.white54),
        const SizedBox(width: 4),
        Container(
          width: metrics.unitSize * 0.7,
          height: metrics.unitSize * 0.7,
          decoration: BoxDecoration(
            color: color ?? _unknownColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white, fontSize: metrics.unitSize),
        ),
      ],
    );
  }
}

/// Les couleurs de la fraîcheur et du risque.
///
/// **Elles viennent du site**, contrairement à celles des zones d'intensité : ce
/// sont celles de la page Performances (`useTrainingPlan.ts`), recopiées à la main
/// comme le site recopie les seuils de densité. Un cycliste qui a vu son orange
/// « productif » le matin doit retrouver le même orange au guidon.
const _formColors = <String?, Color>{
  'very_fresh': Color(0xFF0D6EFD),
  'fresh': Color(0xFF198754),
  'neutral': Color(0xFF6C757D),
  'productive': Color(0xFFFD7E14),
  'overreaching': Color(0xFFDC3545),
};

const _riskColors = <String?, Color>{
  'detraining': Color(0xFF0D6EFD),
  'optimal': Color(0xFF198754),
  'caution': Color(0xFFFD7E14),
  'high_risk': Color(0xFFDC3545),
};

const _doneColor = Color(0xFF198754);
const _doneDimColor = Color(0x8C198754);
const _aheadColor = Color(0xFFFD7E14);
const _overColor = Color(0xFFDC3545);
const _unknownColor = Color(0xFF6C757D);
const _trackColor = Color(0x1FFFFFFF);
