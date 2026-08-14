import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/zone_colors.dart';
import '../../weather/precipitation_forecast_client.dart';
import 'block_card.dart';

/// La prévision de précipitations à 15 minutes (Open-Meteo), pour la position
/// GPS courante — voir `PrecipForecastBlock` (`dashboard_block.dart`).
///
/// Contrairement à [PrecipRadarBlockView] (le radar RainViewer, qu'on lit à
/// l'œil sur une carte), ce bloc répond directement en chiffres à « une averse
/// arrive, et dans combien de temps ? » : une phrase, puis une frise de barres
/// sur les prochaines heures.
///
/// **Remplit toute la case, comme [PrecipRadarBlockView]** — et pas à taille
/// naturelle réduite par [ScaleToFit] comme la plupart des blocs de texte
/// ([BlockCard]/[StatCard]) : une frise de barres profite d'une case généreuse
/// (des barres plus hautes se lisent mieux) là où un chiffre agrandi au-delà
/// du nécessaire ne ferait que détonner à côté de ses voisines. Seul le texte
/// (titre, phrase de tête) garde une taille fixe — c'est la zone des barres qui
/// s'étire ([Expanded]/[LayoutBuilder]), jamais la police.
///
/// Relève une nouvelle prévision à chaque changement de position GPS
/// significatif — [PrecipitationForecastClient] throttle lui-même l'appel
/// réseau (position trop proche ou prévision encore fraîche : la dernière
/// connue est réutilisée telle quelle).
class PrecipForecastBlockView extends StatefulWidget {
  PrecipForecastBlockView({
    super.key,
    required this.recorder,
    this.color,
    this.textColor,
    PrecipitationForecastClient? client,
  }) : client = client ?? PrecipitationForecastClient();

  final RideRecorder recorder;
  final Color? color;
  final Color? textColor;

  /// Injectable pour les tests ; par défaut un client qui parle au vrai proxy
  /// du site.
  final PrecipitationForecastClient client;

  @override
  State<PrecipForecastBlockView> createState() => _PrecipForecastBlockViewState();
}

class _PrecipForecastBlockViewState extends State<PrecipForecastBlockView> {
  PrecipitationForecast? _forecast;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    widget.recorder.addListener(_onRecorderChanged);
    _maybeRefresh();
  }

  @override
  void dispose() {
    widget.recorder.removeListener(_onRecorderChanged);
    super.dispose();
  }

  void _onRecorderChanged() => _maybeRefresh();

  Future<void> _maybeRefresh() async {
    if (_fetching) return;
    final fix = widget.recorder.lastFix;
    if (fix == null) return;

    _fetching = true;
    final forecast = await widget.client.forecastFor(fix.lat, fix.lng);
    _fetching = false;
    if (mounted && forecast != null) setState(() => _forecast = forecast);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.recorder,
      builder: (context, _) {
        final fix = widget.recorder.lastFix;
        if (fix == null) {
          return BlockCard(
            title: 'Orage qui arrive',
            lines: const ['Pas de GPS.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        final forecast = _forecast;
        if (forecast == null || forecast.steps.isEmpty) {
          return BlockCard(
            title: 'Orage qui arrive',
            lines: const ['Prévision indisponible.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        return _PrecipForecastCard(
          forecast: forecast,
          color: widget.color,
          textColor: widget.textColor,
        );
      },
    );
  }
}

/// La carte composée : un titre, la phrase de tête, la frise de barres.
class _PrecipForecastCard extends StatelessWidget {
  const _PrecipForecastCard({required this.forecast, this.color, this.textColor});

  final PrecipitationForecast forecast;
  final Color? color;
  final Color? textColor;

  /// Repli hors contrainte de hauteur (page qui défile, cf. [AveragesCard]) :
  /// la case ne borne alors rien, la frise garde une hauteur raisonnable
  /// plutôt que de s'effondrer à zéro.
  static const _barAreaHeight = 46.0;

  /// La hauteur pleine d'une barre, en mm sur le quart d'heure — au-delà,
  /// l'intensité ne change plus la lecture (« ça déborde du cadre »), c'est
  /// déjà une averse forte. Une pluie légère continue de dessiner une barre
  /// visible (`_heightFractionOf`, plancher à 4 %) plutôt que de disparaître.
  static const _maxMmPerStep = 4.0;

  // Seuils en mm/15 min : repères météo usuels à cette granularité — même
  // valeurs des deux côtés (site et appli), voir la tête de fichier de
  // `CompanionBlockPreview.vue`.
  static const _lightThreshold = 0.1;
  static const _moderateThreshold = 0.5;
  static const _heavyThreshold = 2.0;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(BlockMetrics.natural.padding),
      decoration: BoxDecoration(
        color: color ?? BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bars = _barsRow();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: constraints.hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                'ORAGE QUI ARRIVE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
              ),
              SizedBox(height: metrics.gap),
              Text(
                _headline(),
                style: TextStyle(color: ink, fontSize: metrics.lineSize, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: metrics.gap),
              constraints.hasBoundedHeight ? Expanded(child: bars) : SizedBox(height: _barAreaHeight, child: bars),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Maintenant',
                      style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: metrics.lineSize * 0.75)),
                  Text(_lastLabel(),
                      style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: metrics.lineSize * 0.75)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _barsRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final step in forecast.steps)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor: _heightFractionOf(step.precipitation),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _colorFor(step.precipitation),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  double _heightFractionOf(double mm) => (mm / _maxMmPerStep).clamp(0.04, 1.0);

  /// #D32F2F / #E0C000 / #2E6FD6 : mêmes teintes que `ZONE_COLORS`
  /// (z5/z3/z1) côté éditeur — rouge « ça tombe fort », jaune « ça monte »,
  /// bleu « ça commence ». Translucide en dessous : pas encore de la pluie.
  Color _colorFor(double mm) {
    if (mm >= _heavyThreshold) return const Color(0xFFD32F2F);
    if (mm >= _moderateThreshold) return const Color(0xFFE0C000);
    if (mm >= _lightThreshold) return const Color(0xFF2E6FD6);
    return Colors.white.withValues(alpha: 0.15);
  }

  /// Le premier pas qui dépasse le seuil de pluie légère dit tout : rien
  /// trouvé, c'est sec pour les trois heures qui viennent ; au premier pas,
  /// c'est déjà en train de tomber ; sinon, le délai avant que ça commence.
  String _headline() {
    final idx = forecast.steps.indexWhere((s) => s.precipitation >= _lightThreshold);
    if (idx == -1) return 'Pas de pluie prévue.';
    if (idx == 0) return 'Pluie en cours.';
    return 'Averse dans ${idx * 15} min.';
  }

  String _lastLabel() {
    final totalMinutes = forecast.steps.length * 15;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '+$minutes min';
    if (minutes == 0) return '+${hours}h';
    return '+${hours}h${minutes.toString().padLeft(2, '0')}';
  }
}
