import 'package:flutter/material.dart';

import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../../ui/zone_colors.dart';
import 'swipe_zone.dart';

/// Le bandeau du bas : les valeurs instantanées de la sortie.
///
/// Présent sur toutes les pages, y compris la carte. Un glissé horizontal
/// dessus **change de jeu de valeurs**, pas de page : le bandeau n'a rien en
/// dessous de lui, donc un geste qui y démarre lui appartient sans ambiguïté, et
/// c'est le seul endroit où l'on peut faire défiler des chiffres sans les
/// perdre de vue. Changer de page, c'est l'affaire des bandes du bord de la
/// carte et des pastilles, à droite d'ici.
///
/// **Les jeux de valeurs viennent du profil de sortie**, plus d'une énumération :
/// c'est le site qui dit lesquels, dans quel ordre, et avec quelles mesures. Ce
/// qui ne change pas, c'est la limite de quatre cases — au-delà, les chiffres
/// deviennent trop petits pour être lus d'un coup d'œil en roulant, ce qui est
/// le seul usage du bandeau (garantie tenue par `RideBandSpec.parse`).
///
/// Il ne réutilise pas [MetricTile] : celui-ci empile icône, valeur et unité
/// pour l'écran de diagnostic et réclame une soixantaine de points de haut. Ici
/// chaque point pris est un point de carte perdu.
class RideBottomBand extends StatefulWidget {
  const RideBottomBand({
    super.key,
    required this.bands,
    required this.sources,
    required this.page,
    required this.pageCount,
    required this.onGoToPage,
    this.onCalibratePower,
  });

  /// Les jeux de valeurs du profil, dans l'ordre. Au moins un.
  final List<RideBandSpec> bands;

  /// D'où les mesures se lisent — et de quoi elles dépendent.
  final MetricSources sources;

  /// La page affichée et leur nombre, pour les pastilles.
  final int page;
  final int pageCount;

  /// Demande de changement de page — la coquille possède le contrôleur.
  final void Function(int page) onGoToPage;

  /// Calibrer le capteur de puissance, sur un tap des watts ou de leur zone.
  ///
  /// La case des watts est le seul endroit de l'écran où l'on *constate* une
  /// puissance qui dérive : c'est là qu'on tape, pas dans un menu deux pages
  /// plus loin. Non filtré ici, contrairement au menu de la page de données —
  /// la coquille ne se reconstruit pas quand le capteur finit sa découverte, et
  /// un tap devenu inerte entre-temps se lirait comme une appli figée. C'est la
  /// boîte de dialogue qui dit pourquoi, le cas échéant.
  final VoidCallback? onCalibratePower;

  /// Hauteur du contenu, hors zone système. Le bandeau s'étire ensuite de
  /// [MediaQueryData.viewPadding] vers le bas pour que ses valeurs ne passent
  /// pas sous la barre de navigation d'Android.
  static const contentHeight = 72.0;

  /// Ce que le bandeau occupe réellement, zone système comprise. La coquille
  /// s'en sert pour poser le haut de la carte.
  static double heightFor(BuildContext context) =>
      contentHeight + MediaQuery.viewPaddingOf(context).bottom;

  @override
  State<RideBottomBand> createState() => _RideBottomBandState();
}

class _RideBottomBandState extends State<RideBottomBand> {
  /// Le jeu de valeurs affiché. Il ne suit pas la page : on peut très bien
  /// vouloir ses zones de puissance en gardant la carte sous les yeux.
  int _set = 0;

  /// La liste est refermée sur elle-même — après le dernier revient le premier —
  /// parce qu'un bout de course voudrait dire « glissé sans effet », et un geste
  /// sans effet se prend pour une panne.
  void _onSwipe(int direction) => setState(
        () => _set = (_set + direction) % widget.bands.length,
      );

  @override
  void didUpdateWidget(RideBottomBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changer de profil en cours de route peut raccourcir la liste : sans ce
    // rattrapage, l'index resterait au-delà du dernier jeu et la construction
    // suivante lèverait, en pleine sortie.
    if (_set >= widget.bands.length) _set = 0;
  }

  @override
  Widget build(BuildContext context) {
    return SwipeZone(
      onSwipe: _onSwipe,
      child: Container(
        height: RideBottomBand.heightFor(context),
        decoration: const BoxDecoration(
          color: Color(0xFF101214),
          border: Border(top: BorderSide(color: Colors.white24)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Row(
                  children: [
                    for (final metric in widget.bands[_set].metrics)
                      Expanded(child: _metric(metric)),
                    _PageDots(
                      current: widget.page,
                      count: widget.pageCount,
                      onTap: widget.onGoToPage,
                    ),
                  ],
                ),
              ),
            ),
            // Le rappel du jeu affiché, tout en haut : à peine visible, mais
            // c'est ce qui distingue « j'ai glissé » de « le bandeau a changé
            // tout seul ». Un seul jeu, rien à rappeler.
            if (widget.bands.length > 1)
              Positioned(
                top: 3,
                left: 0,
                right: 0,
                child: Center(
                  child: _SetDots(current: _set, count: widget.bands.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(MetricId metric) {
    final tile = ListenableBuilder(
      listenable: Listenable.merge(metric.dependencies(widget.sources)),
      builder: (context, _) {
        final reading = metric.read(widget.sources);
        return _BandMetric(
          value: reading.value,
          label: metric.unit,
          zoneKey: reading.zoneKey,
        );
      },
    );

    final calibrate = widget.onCalibratePower;
    if (calibrate == null || !_isPower(metric)) return tile;

    // Le tap et le glissé du bandeau ne se disputent pas : l'arène donne le
    // geste au tap seulement si le doigt s'est levé sans partir de côté, donc
    // un glissé qui commence sur les watts change bien de jeu de valeurs.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: calibrate,
      child: tile,
    );
  }

  static bool _isPower(MetricId metric) =>
      metric == MetricId.power || metric == MetricId.powerZone;
}

/// Une valeur du bandeau : le chiffre, puis son unité en dessous.
///
/// Un tiret quand la mesure manque, jamais un zéro — même règle que
/// [MetricTile], pour que le bandeau et l'écran de diagnostic ne racontent pas
/// deux histoires différentes du même capteur muet.
class _BandMetric extends StatelessWidget {
  const _BandMetric({required this.value, required this.label, this.zoneKey});

  final String? value;
  final String label;

  /// `z1`…`z7` pour peindre la case aux couleurs de la zone, `null` pour la
  /// laisser sur le fond du bandeau.
  final String? zoneKey;

  @override
  Widget build(BuildContext context) {
    final background = zoneColorOf(zoneKey);
    final foreground = background == null ? Colors.white : foregroundOf(background);

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Les valeurs sont de longueurs très inégales (« 8 » et « 1:12:34 ») et
        // le bandeau partage sa largeur en parts égales : sans réduction, la
        // durée déborderait sur un téléphone étroit.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value ?? '—',
            maxLines: 1,
            style: TextStyle(
              color: foreground,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          // Sur un aplat de zone, le libellé passe de « discret » à « lisible » :
          // le blanc à 54 % disparaît sur le jaune comme sur le rouge.
          style: TextStyle(
            color: background == null ? Colors.white54 : foreground.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );

    if (background == null) return content;

    // La marge du haut dégage les pastilles du jeu de valeurs, posées à 3 pt du
    // bord : sans elle, l'aplat de la case du milieu passerait dessous.
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 9, 2, 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }
}

/// Les pastilles de page, à l'extrémité du bandeau.
///
/// Elles disent où on est, et permettent d'y aller directement : le glissé sur
/// le bord de la carte est pratique à deux pages, il l'est moins à cinq — et un
/// profil peut en avoir cinq.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.current,
    required this.count,
    required this.onTap,
  });

  final int current;
  final int count;
  final void Function(int page) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var page = 0; page < count; page++)
            GestureDetector(
              onTap: () => onTap(page),
              behavior: HitTestBehavior.opaque,
              // La pastille fait 8 points, sa zone tactile 22 : à vélo, on vise
              // mal.
              child: SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: page == current ? Colors.white : Colors.white30,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Les pastilles du jeu de valeurs, en haut du bandeau.
///
/// Horizontales, contrairement à celles des pages : elles disent dans quel sens
/// glisser. Et minuscules — c'est un repère, pas une commande ; on change de jeu
/// en glissant sur le bandeau, qui offre une cible autrement plus large qu'un
/// point de quatre points de côté.
class _SetDots extends StatelessWidget {
  const _SetDots({required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var set = 0; set < count; set++)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: set == current ? Colors.white54 : Colors.white24,
            ),
          ),
      ],
    );
  }
}
