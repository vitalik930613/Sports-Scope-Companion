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
/// carte ; savoir où l'on vient d'arriver, celle de `RidePageFlash`.
///
/// **Il ne porte plus aucun repère de position** — ni la colonne de pastilles de
/// page à son extrémité, ni la rangée de pastilles de jeu de valeurs sur son
/// bord haut. Les deux étaient dessinées à huit et quatre points de côté dans un
/// bandeau de soixante-douze de haut : lisibles à l'arrêt, c'est-à-dire au seul
/// moment où l'on sait déjà où l'on est. Et la colonne des pages débordait dès
/// qu'un profil en comptait quatre — vingt-deux points par pastille, il n'y en
/// avait la place que de trois. Toute la hauteur va donc aux chiffres, qui sont
/// ce qu'on vient y lire.
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
    this.onCalibratePower,
  });

  /// Les jeux de valeurs du profil, dans l'ordre. Au moins un.
  final List<RideBandSpec> bands;

  /// D'où les mesures se lisent — et de quoi elles dépendent.
  final MetricSources sources;

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
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Row(
            children: [
              for (final (index, metric) in widget.bands[_set].metrics.indexed)
                Expanded(child: _metric(metric, index)),
            ],
          ),
        ),
      ),
    );
  }

  /// Noir (le fond du bandeau lui-même) et l'anthracite des cartes ailleurs
  /// dans la sortie — en alternance pour que deux chiffres voisins ne se
  /// confondent pas en une seule masse. La couleur de zone, quand il y en a
  /// une, garde toujours la priorité : c'est elle, l'information.
  static const _alternateBackgrounds = [Color(0xFF101214), Color(0xFF1F2226)];

  Widget _metric(MetricId? metric, int index) {
    // Une case vide reste dans la rangée — le glissé de largeur du `Row`
    // parent dépend du nombre de cases, pas de leur contenu — mais n'y
    // dessine rien.
    if (metric == null) return const SizedBox.shrink();

    final tile = ListenableBuilder(
      listenable: Listenable.merge(metric.dependencies(widget.sources)),
      builder: (context, _) {
        final reading = metric.read(widget.sources);
        return _BandMetric(
          value: reading.value,
          // Le nom de la mesure, pas son unité : dans une case sans icône,
          // c'est ce qui dit laquelle on regarde (« Cardio », pas « bpm »).
          label: metric.name,
          zoneKey: reading.zoneKey,
          background: reading.background,
          altBackground: _alternateBackgrounds[index % 2],
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
  const _BandMetric({
    required this.value,
    required this.label,
    this.zoneKey,
    this.background,
    this.altBackground,
  });

  final String? value;
  final String label;

  /// `z1`…`z7` pour peindre la case aux couleurs de la zone, `null` pour la
  /// laisser sur le fond du bandeau.
  final String? zoneKey;

  /// Couleur de fond directe (la pente, sur sa tranche de difficulté), quand
  /// la mesure ne se range pas en zone d'entraînement. Même priorité que
  /// [MetricView] : elle l'emporte sur l'alternance noir/anthracite.
  final Color? background;

  /// Le noir ou l'anthracite de l'alternance, quand la case ne porte pas de
  /// zone — c'est elle qui recule dès qu'une zone donne une vraie couleur.
  final Color? altBackground;

  @override
  Widget build(BuildContext context) {
    final zoneColor = background ?? zoneColorOf(zoneKey);
    final foreground = zoneColor == null ? Colors.white : foregroundOf(zoneColor);

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
            color: zoneColor == null ? Colors.white54 : foreground.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );

    final surface = zoneColor ?? altBackground;
    if (surface == null) return content;

    // Symétrique depuis que les pastilles du jeu de valeurs ont quitté le bord
    // haut : la marge de 9 pt qui les dégageait ne tenait plus qu'à elles, et
    // l'aplat de zone gagne à couvrir toute la hauteur de sa case — c'est aussi
    // une surface de lecture.
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 3, 2, 3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }
}
