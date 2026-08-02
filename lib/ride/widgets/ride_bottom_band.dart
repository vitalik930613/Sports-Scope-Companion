import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
import '../../account/rider_profile_store.dart';
import '../../ble/sensor_hub.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import '../nav_state.dart';
import '../ride_pages.dart';
import 'swipe_zone.dart';

/// Les jeux de valeurs du bandeau.
///
/// Quatre cases, pas plus : au-delà, les chiffres deviennent trop petits pour
/// être lus d'un coup d'œil en roulant, ce qui est le seul usage du bandeau. Ce
/// qui ne tient pas passe donc dans le jeu suivant, à un glissé de là.
enum RideBandSet {
  /// L'avancement de la sortie : ce qu'on regarde le plus souvent.
  ride,

  /// L'effort : le cardio et la puissance, chacun avec sa zone.
  effort;

  static int get count => RideBandSet.values.length;

  /// Le jeu qu'on atteint en glissant dans ce sens. La liste est refermée sur
  /// elle-même — après le dernier revient le premier — parce qu'à deux jeux, un
  /// bout de course voudrait dire « glissé sans effet », et un geste sans effet
  /// se prend pour une panne.
  RideBandSet stepped(int direction) =>
      RideBandSet.values[(index + direction) % count];
}

/// Le bandeau du bas : les valeurs instantanées de la sortie.
///
/// Présent sur toutes les pages, y compris la carte. Un glissé horizontal
/// dessus **change de jeu de valeurs**, pas de page : le bandeau n'a rien en
/// dessous de lui, donc un geste qui y démarre lui appartient sans ambiguïté, et
/// c'est le seul endroit où l'on peut faire défiler des chiffres sans les
/// perdre de vue. Changer de page, c'est l'affaire des bandes du bord de la
/// carte et des pastilles, à droite d'ici.
///
/// Il ne réutilise pas [MetricTile] : celui-ci empile icône, valeur et unité
/// pour l'écran de diagnostic et réclame une soixantaine de points de haut. Ici
/// chaque point pris est un point de carte perdu.
class RideBottomBand extends StatefulWidget {
  const RideBottomBand({
    super.key,
    required this.hub,
    required this.recorder,
    required this.nav,
    required this.riderProfile,
    required this.page,
    required this.onGoToPage,
    this.onCalibratePower,
  });

  final SensorHub hub;
  final RideRecorder recorder;
  final ValueListenable<NavState?> nav;

  /// Les seuils du cycliste, d'où sortent les zones. Vides tant que la page du
  /// site ne les a pas poussés — le bandeau affiche alors un tiret, jamais une
  /// zone devinée à partir d'un seuil par défaut.
  final RiderProfileStore riderProfile;

  /// La page affichée, pour les pastilles.
  final RidePage page;

  /// Demande de changement de page — la coquille possède le contrôleur.
  final void Function(RidePage page) onGoToPage;

  /// Calibrer le capteur de puissance, sur un tap des watts ou de leur zone.
  ///
  /// La case des watts est le seul endroit de l'écran où l'on *constate* une
  /// puissance qui dérive : c'est là qu'on tape, pas dans un menu deux pages
  /// plus loin. Non filtré ici, contrairement au menu de la page Effort — la
  /// coquille ne se reconstruit pas quand le capteur finit sa découverte, et un
  /// tap devenu inerte entre-temps se lirait comme une appli figée. C'est la
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
  RideBandSet _set = RideBandSet.ride;

  void _onSwipe(int direction) =>
      setState(() => _set = _set.stepped(direction));

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
                    for (final metric in _metrics()) Expanded(child: metric),
                    _PageDots(current: widget.page, onTap: widget.onGoToPage),
                  ],
                ),
              ),
            ),
            // Le rappel du jeu affiché, tout en haut : à peine visible, mais
            // c'est ce qui distingue « j'ai glissé » de « le bandeau a changé
            // tout seul ».
            Positioned(
              top: 3,
              left: 0,
              right: 0,
              child: Center(child: _SetDots(current: _set)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _metrics() => switch (_set) {
        RideBandSet.ride => [
            _duration(),
            _distance(),
            _speed(),
            _power(asZone: false),
          ],
        RideBandSet.effort => [
            _heartRate(asZone: false),
            _heartRate(asZone: true),
            _power(asZone: false),
            _power(asZone: true),
          ],
      };

  /// Durée et distance viennent de l'enregistreur, pas de la page : hors
  /// enregistrement elles n'existent pas, et un zéro ferait croire à un compteur
  /// remis à zéro plutôt qu'à une sortie non lancée.
  Widget _duration() => ListenableBuilder(
        listenable: widget.recorder,
        builder: (context, _) => _BandMetric(
          value: widget.recorder.isActive
              ? formatDuration(widget.recorder.recorded)
              : null,
          label: 'durée',
        ),
      );

  Widget _distance() => ListenableBuilder(
        listenable: widget.recorder,
        builder: (context, _) => _BandMetric(
          value: widget.recorder.isActive
              ? formatDistance(widget.recorder.distanceM)
              : null,
          label: 'distance',
        ),
      );

  /// La vitesse vient de la page : c'est elle qui tient le GPS de la navigation,
  /// et elle la publie déjà à chaque position.
  ///
  /// Un état périmé ne s'affiche pas — une vitesse figée à 34 km/h à l'arrêt
  /// serait pire que pas de vitesse du tout. Le bandeau se redessine à chaque
  /// message, donc le tiret apparaît dès la première seconde qui suit la reprise
  /// d'un autre rafraîchissement.
  Widget _speed() => ValueListenableBuilder<NavState?>(
        valueListenable: widget.nav,
        builder: (context, nav, _) => _BandMetric(
          value: nav == null || nav.isStale(DateTime.now())
              ? null
              : nav.speedKmh.toStringAsFixed(1).replaceAll('.', ','),
          label: 'km/h',
        ),
      );

  Widget _heartRate({required bool asZone}) => _effortMetric(
        listenable: widget.hub.latestHeartRate,
        unit: 'bpm',
        threshold: 'LTHR ?',
        hasZones: (profile) => profile.hasHrZones,
        zoneOf: (profile, value) => profile.hrZoneFor(value),
        asZone: asZone,
      );

  /// La puissance se lit exactement comme le cardio, zone comprise.
  ///
  /// Elle est restée longtemps sans couleur, faute de palette qui fasse
  /// autorité sur sept zones. Mais un bandeau à moitié peint se lit mal :
  /// l'œil, habitué à trouver l'intensité dans la couleur, ne la cherche plus
  /// dans le chiffre gris d'à côté. Le dégradé prolongé (cf. `zone_colors.dart`)
  /// vaut mieux que cette asymétrie.
  Widget _power({required bool asZone}) {
    final metric = _effortMetric(
      listenable: widget.hub.latestPower,
      unit: 'W',
      threshold: 'FTP ?',
      hasZones: (profile) => profile.hasPowerZones,
      zoneOf: (profile, value) => profile.powerZoneFor(value),
      asZone: asZone,
    );

    final calibrate = widget.onCalibratePower;
    if (calibrate == null) return metric;

    // Le tap et le glissé du bandeau ne se disputent pas : l'arène donne le
    // geste au tap seulement si le doigt s'est levé sans partir de côté, donc
    // un glissé qui commence sur les watts change bien de jeu de valeurs.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: calibrate,
      child: metric,
    );
  }

  /// Une mesure d'effort, ou sa zone, sur le fond de la zone du moment.
  ///
  /// Les deux cases sont peintes, et pas seulement celle de la zone : c'est le
  /// chiffre qu'on regarde en roulant, et lui donner la couleur évite d'avoir à
  /// lire la case d'à côté pour savoir si 158 bpm est confortable ou non. Elles
  /// se calculent à partir du même couple mesure + profil, pour ne jamais
  /// afficher deux zones différentes le temps d'une trame.
  ///
  /// Deux façons pour la zone d'être vide, et **pas** le même affichage : un
  /// tiret quand le capteur se tait — même règle que partout ailleurs — mais
  /// « LTHR ? » ou « FTP ? » quand c'est le seuil qui manque. Le tiret seul se
  /// lisait comme un capteur débranché, et cachait la seule des deux causes que
  /// le cycliste puisse corriger, sur le site, avant de partir. Le nom du seuil
  /// manquant tient dans la case, ce qui n'était pas acquis : [_BandMetric]
  /// réduit sa valeur jusqu'à ce qu'elle rentre.
  ///
  /// Sans zones connues, la mesure reste sur le fond du bandeau : une couleur
  /// inventée serait pire qu'une couleur absente.
  Widget _effortMetric({
    required ValueListenable<int?> listenable,
    required String unit,
    required String threshold,
    required bool Function(RiderProfile profile) hasZones,
    required TrainingZone? Function(RiderProfile profile, int value) zoneOf,
    required bool asZone,
  }) =>
      ListenableBuilder(
        listenable: widget.riderProfile,
        builder: (context, _) => ValueListenableBuilder<int?>(
          valueListenable: listenable,
          builder: (context, value, _) {
            final profile = widget.riderProfile.profile;
            final zone = value == null ? null : zoneOf(profile, value);

            if (!asZone) {
              return _BandMetric(
                value: value?.toString(),
                label: unit,
                zoneKey: zone?.key,
              );
            }
            // Le seuil passe avant le capteur : sans zones, aucune mesure ne
            // donnera jamais de zone, et c'est ça qu'il faut dire — y compris
            // quand le capteur, lui, est muet.
            if (!hasZones(profile)) {
              return _BandMetric(value: threshold, label: 'zone $unit');
            }
            return _BandMetric(
              value: zone?.key.toUpperCase(),
              label: 'zone $unit',
              zoneKey: zone?.key,
            );
          },
        ),
      );
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
/// le bord de la carte est pratique à deux pages, il le sera moins à cinq.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.current, required this.onTap});

  final RidePage current;
  final void Function(RidePage page) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final page in RidePage.values)
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
  const _SetDots({required this.current});

  final RideBandSet current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final set in RideBandSet.values)
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
