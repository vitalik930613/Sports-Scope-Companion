import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
import '../../account/rider_profile_store.dart';
import '../../recording/gps_source.dart';
import '../../recording/ride_recorder.dart';
import '../../recording/ride_stats.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import '../nav_state.dart';
import '../zone_time.dart';

/// La page « Effort » : où en est la sortie, côté corps.
///
/// Elle répond à une question que le bandeau ne peut pas poser — le bandeau dit
/// l'instant (158 bpm, Z3), celle-ci dit le cumul : combien de temps passé dans
/// chaque zone, quelles moyennes. C'est ce qu'on regarde à l'arrêt d'un col ou
/// au feu rouge, pas en roulant, d'où le format en cartes et non en gros
/// chiffres.
///
/// Tout vient de [RideRecorder] : hors enregistrement il n'y a **rien** à
/// afficher, et la page le dit plutôt que d'exhiber des zéros. Les zones, elles,
/// viennent du site via [RiderProfileStore] — jamais d'un seuil deviné ici.
///
/// Opaque, et pas seulement dessinée par-dessus : la carte reste montée et
/// peinte en dessous, mais on ne doit pas la voir transparaître.
class RideSummaryPage extends StatelessWidget {
  const RideSummaryPage({
    super.key,
    required this.recorder,
    required this.nav,
    required this.riderProfile,
    this.onChooseRoute,
    this.onClearRoute,
    this.onCalibratePower,
    this.onLeaveRide,
  });

  final RideRecorder recorder;
  final ValueListenable<NavState?> nav;
  final RiderProfileStore riderProfile;

  /// Changer de tracé, ou retirer celui qu'on suit. Confiés à la coquille, qui
  /// possède le WebView : la page ne sait pas naviguer, elle sait demander.
  ///
  /// Facultatifs : sans eux le menu ne s'affiche pas. La page se monte aussi
  /// hors d'une sortie (tests, futurs écrans), et un menu qui ne mènerait nulle
  /// part vaut moins que pas de menu.
  final VoidCallback? onChooseRoute;
  final VoidCallback? onClearRoute;

  /// Calibrer le capteur de puissance. Fourni par la coquille seulement quand
  /// un capteur connecté sait le faire — le menu ne montre pas une commande qui
  /// n'aurait que « non » à répondre.
  final VoidCallback? onCalibratePower;

  /// Rentrer : fermer la sortie et retrouver l'accueil.
  ///
  /// Ici parce qu'il n'y avait **aucun chemin nommé** pour sortir — le bouton
  /// retour du téléphone, et lui seul, ce qui laissait le cycliste appuyer
  /// plusieurs fois sans savoir combien. Une commande écrite en toutes lettres
  /// répond à la question « comment on rentre ? », qu'un geste ne répond
  /// jamais.
  final VoidCallback? onLeaveRide;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16181B),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _title(),
            const SizedBox(height: 16),
            _recordingControl(),
            _zoneBreakdowns(),
            const SizedBox(height: 12),
            _effort(),
            const SizedBox(height: 12),
            _navReadout(),
          ],
        ),
      ),
    );
  }

  /// Le titre, et le menu de l'itinéraire au bout.
  ///
  /// Ici et pas sur la carte : la carte est faite pour être regardée en
  /// roulant, et tout ce qu'on y pose vole des pixels à ce qu'on y cherche.
  /// Cette page-ci se consulte à l'arrêt — c'est déjà l'endroit où l'on pilote
  /// l'enregistrement, le menu y est chez lui.
  Widget _title() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Effort',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onChooseRoute != null ||
            onClearRoute != null ||
            onCalibratePower != null ||
            onLeaveRide != null)
          _actionsMenu(),
      ],
    );
  }

  /// Les actions rares de la sortie : changer de tracé, le retirer, calibrer la
  /// puissance.
  ///
  /// Un menu et pas des boutons : ce sont des actions rares — on part avec son
  /// itinéraire et un capteur qu'on croit juste — et des aplats de plus en tête
  /// de page attireraient le pouce au détriment de l'enregistrement, qui est la
  /// commande qu'on vient réellement chercher ici.
  ///
  /// « Retirer » n'apparaît que s'il y a quelque chose à retirer, et c'est la
  /// page web qui le dit : elle seule sait ce qu'elle suit vraiment, y compris
  /// un tracé restauré depuis son stockage ou une destination posée à la main
  /// sur la carte. Sans état reçu, on ne prétend pas savoir.
  Widget _actionsMenu() => ValueListenableBuilder<NavState?>(
        valueListenable: nav,
        builder: (context, state, _) => PopupMenuButton<VoidCallback>(
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          tooltip: 'Actions',
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            if (onChooseRoute case final choose?)
              PopupMenuItem(
                value: choose,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.route),
                  title: Text('Choisir un autre itinéraire'),
                ),
              ),
            if (onClearRoute case final clear? when state?.onRoute == true)
              PopupMenuItem(
                value: clear,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.layers_clear),
                  title: Text('Retirer l\'itinéraire'),
                ),
              ),
            if (onCalibratePower case final calibrate?)
              PopupMenuItem(
                value: calibrate,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bolt),
                  title: Text('Calibrer la puissance'),
                ),
              ),
            // En dernier, après un séparateur : les autres commandes restent
            // dans la sortie, celle-ci en sort. Les mettre au même rang ferait
            // quitter la navigation d'un pouce qui visait « calibrer ».
            if (onLeaveRide case final leave?) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                value: leave,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.home_outlined),
                  title: Text('Revenir à l\'accueil'),
                ),
              ),
            ],
          ],
        ),
      );

  /// Piloter l'enregistrement sans quitter la sortie : démarrer, suspendre,
  /// reprendre.
  ///
  /// Il n'y avait rien : l'enregistrement se décidait au départ, dans la boîte de
  /// dialogue de l'écran des capteurs, et refuser était sans retour. Or c'est
  /// exactement ici qu'on s'en aperçoit — cette page est vide tant que rien n'est
  /// enregistré, et c'est ce vide qui rappelle qu'on a dit non.
  ///
  /// **Toujours rien pour arrêter.** Une pause ne perd rien — le fichier reste
  /// ouvert, la sortie repart d'un tap — alors qu'un arrêt clôt la sortie. Un
  /// bouton qui termine, à portée de pouce sur une page qu'on consulte en
  /// roulant, coûterait un jour une sortie entière ; on termine au retour, depuis
  /// l'écran des capteurs.
  ///
  /// Les deux commandes n'ont pas le même poids visuel, et c'est voulu :
  /// suspendre est discret (on ne le cherche qu'en connaissance de cause),
  /// reprendre est large et coloré, parce qu'une pause oubliée est la seule
  /// façon de perdre la fin d'une sortie sans s'en apercevoir.
  Widget _recordingControl() => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final Widget control = switch (recorder.state) {
            RecorderState.idle => _StartRecordingButton(recorder: recorder),
            RecorderState.recording => _PauseButton(recorder: recorder),
            RecorderState.paused => _ResumeBanner(recorder: recorder),
          };

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: control,
          );
        },
      );

  /// Les deux répartitions du temps, cardio puis puissance.
  ///
  /// Écoute pour les deux : les histogrammes grossissent à chaque point capturé
  /// et les zones arrivent du site en cours de sortie, donc le temps déjà écoulé
  /// doit pouvoir se recolorer d'un coup — c'est tout l'intérêt de garder un
  /// histogramme plutôt qu'un compteur par zone.
  ///
  /// Hors enregistrement, **une seule carte pour les deux** : le message serait
  /// identique, et deux fois de suite il se lirait comme un bégaiement de
  /// l'appli plutôt que comme deux répartitions qui attendent leur premier
  /// point.
  Widget _zoneBreakdowns() => ListenableBuilder(
        listenable: Listenable.merge([recorder, riderProfile]),
        builder: (context, _) {
          if (!recorder.isActive) {
            return const _Card(
              title: 'Temps par zone',
              lines: ['La répartition se remplit dès le départ.'],
            );
          }
          return Column(
            children: [
              _hrZones(),
              const SizedBox(height: 12),
              _powerZones(),
            ],
          );
        },
      );

  /// Le temps passé dans chaque zone cardio depuis le départ.
  Widget _hrZones() => _zones(
        title: 'Temps par zone cardio',
        histogram: recorder.stats.hrHistogram,
        bucket: RideStats.hrBucketBpm,
        zones: riderProfile.profile.hrZones,
        noMeasure: 'Pas encore de cardio mesuré.',
        noThreshold: 'Seuil cardiaque inconnu du site : pas de zones.',
        latest: recorder.hub.latestHeartRate,
        zoneOf: (value) => riderProfile.profile.hrZoneFor(value)?.key,
        currentIcon: Icons.favorite,
      );

  /// Le même cumul, côté puissance.
  ///
  /// Deux cartes plutôt qu'une à bascule : les deux répartitions ne racontent
  /// pas la même sortie — le cardio traîne derrière l'effort et lisse les
  /// relances, la puissance les compte toutes. Les mettre l'une au-dessus de
  /// l'autre, c'est justement pouvoir lire cet écart ; un sélecteur obligerait
  /// à mémoriser la première pour la comparer à la seconde.
  ///
  /// Sept zones ici contre cinq là, sans que rien ne le déclare : la liste vient
  /// du site, et [zoneSharesOf] dessine ce qu'on lui donne.
  Widget _powerZones() => _zones(
        title: 'Temps par zone de puissance',
        histogram: recorder.stats.powerHistogram,
        bucket: RideStats.powerBucketW,
        zones: riderProfile.profile.powerZones,
        noMeasure: 'Pas encore de puissance mesurée.',
        noThreshold: 'FTP inconnue du site : pas de zones.',
        latest: recorder.hub.latestPower,
        zoneOf: (value) => riderProfile.profile.powerZoneFor(value)?.key,
        currentIcon: Icons.bolt,
      );

  /// La répartition du temps d'une mesure dans les zones du cycliste.
  ///
  /// N'écoute rien elle-même : [_zoneBreakdowns] la reconstruit à chaque point
  /// et à chaque profil reçu. Elle n'est donc appelée qu'en enregistrement, et
  /// n'a pas à redire ce qui se passe avant le départ.
  ///
  /// La seule chose que cette carte emprunte à l'instant, c'est **où l'on se
  /// trouve** : la ligne de la zone courante est peinte de sa couleur, faute de
  /// quoi le cumul ne se rattache à rien de ce qu'on ressent en pédalant.
  Widget _zones({
    required String title,
    required Map<int, int> histogram,
    required int bucket,
    required List<TrainingZone> zones,
    required String noMeasure,
    required String noThreshold,
    required ValueListenable<int?> latest,
    required String? Function(int value) zoneOf,
    required IconData currentIcon,
  }) {
    final shares = zoneSharesOf(
      histogram,
      bucket: bucket,
      zones: zones,
      perPoint: recorder.tickPeriod,
    );

    // Deux façons d'être vide, et pas le même message : sans zones, aucune
    // mesure n'en donnera jamais, et c'est le site qu'il faut aller voir — pas
    // le capteur.
    if (shares.isEmpty) {
      return _Card(
        title: title,
        lines: [zones.isEmpty ? noThreshold : noMeasure],
      );
    }

    // La zone du moment vient du hub, comme celle du bandeau, et non de
    // l'histogramme : celui-ci ne dit pas *quand* une mesure est tombée, et son
    // dernier palier rempli peut dater du col d'il y a une heure. Même source
    // des deux côtés, donc jamais deux zones différentes à l'écran au même
    // instant.
    return ValueListenableBuilder<int?>(
      valueListenable: latest,
      builder: (context, value, _) => _ZoneBreakdown(
        title: title,
        shares: shares,
        current: value == null ? null : zoneOf(value),
        currentIcon: currentIcon,
      ),
    );
  }

  /// Les moyennes de la sortie, cardio et puissance côte à côte.
  Widget _effort() => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final stats = recorder.stats;
          if (!recorder.isActive) {
            return const _Card(
              title: 'Sortie non lancée',
              lines: ['Les moyennes se remplissent dès le départ.'],
            );
          }
          return Column(
            children: [
              // `IntrinsicHeight` et pas un simple `stretch` : dans une liste,
              // la hauteur disponible est infinie, et une colonne étirée vers
              // l'infini fait exploser la mise en page. Il faut donc mesurer la
              // plus haute des deux cartes avant de les aligner.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Card(
                        title: 'Cardio',
                        lines: [
                          '${_or(stats.avgHeartRate)} bpm moyen',
                          'Max ${_or(stats.maxHeartRate)} bpm',
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Card(
                        title: 'Puissance',
                        lines: [
                          '${_or(stats.avgPower)} W moyen',
                          'Normalisée ${_or(stats.normalizedPowerW)} W',
                          'Max ${_or(stats.maxPower)} W',
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                title: 'Sortie',
                lines: [
                  'Cadence ${_or(stats.avgCadence)} tr/min moyenne',
                  'Dénivelé positif ${stats.ascentM.round()} m',
                  // Le tiret dit ici « pas de capteur de puissance », le seul
                  // cas où l'on ne sait pas : les calories se déduisent du
                  // travail mécanique, jamais du cardio (cf. RideStats).
                  'Dépense ${_or(stats.calories)} kcal',
                ],
              ),
            ],
          );
        },
      );

  /// Ce que la page de navigation raconte d'elle-même.
  ///
  /// Provisoire, mais pas gratuit : c'est le seul moyen de vérifier sur la route
  /// que le pont livre bien un état frais quand la carte est masquée — ce dont
  /// dépendra le retour automatique à l'approche d'un virage.
  Widget _navReadout() => ValueListenableBuilder<NavState?>(
        valueListenable: nav,
        builder: (context, state, _) {
          if (state == null) {
            return const _Card(
              title: 'Navigation',
              lines: ['Aucun état reçu de la page.'],
            );
          }
          final turn = state.turn;
          return _Card(
            title: 'Navigation',
            lines: [
              if (!state.onRoute) 'Navigation libre',
              if (state.onRoute)
                'Restant : ${(state.remainingM / 1000).toStringAsFixed(1)} km '
                    '· ${state.remainingGainM.round()} m D+',
              if (turn == null) 'Pas de virage annoncé',
              if (turn != null)
                'Virage ${turn.phase.name} à ${turn.distM.round()} m'
                    '${turn.direction == null ? '' : ' (${turn.direction})'}',
              if (state.offRoute) 'Hors trace',
              if (state.arrived) 'Arrivé',
              if (state.isStale(DateTime.now())) 'État périmé',
            ],
          );
        },
      );

  static String _or(num? value) => value?.toString() ?? '—';
}

/// Le bouton de départ, et son attente.
///
/// À part parce qu'il a un état : `start()` prend le temps d'obtenir une
/// position, et sans ce verrou un pouce impatient sur une piste cyclable en
/// lancerait trois.
class _StartRecordingButton extends StatefulWidget {
  const _StartRecordingButton({required this.recorder});

  final RideRecorder recorder;

  @override
  State<_StartRecordingButton> createState() => _StartRecordingButtonState();
}

class _StartRecordingButtonState extends State<_StartRecordingButton> {
  bool _starting = false;

  Future<void> _start() async {
    // Le messager est pris avant l'attente : après, le `context` peut avoir
    // disparu si le cycliste a changé de page entre-temps.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    try {
      await widget.recorder.start();
    } on GpsUnavailable catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $e')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        // Haut : le doigt vise mal sur une route bosselée, et cette page se
        // consulte à l'arrêt ou au feu rouge.
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: _starting ? null : _start,
        icon: _starting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fiber_manual_record, color: Colors.red),
        label: Text(
          _starting
              // Ce n'est pas une politesse : `start()` attend une vraie position,
              // ce qui peut durer plusieurs secondes sous les arbres.
              ? 'Recherche du GPS…'
              : 'Démarrer l\'enregistrement',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

/// Suspendre l'enregistrement : discret, et sans confirmation.
///
/// Discret parce qu'on ne le cherche qu'en connaissance de cause — un café, une
/// crevaison — et qu'un aplat de plus en haut de page attirerait le pouce pour
/// rien. Sans confirmation parce qu'une pause ne coûte rien : elle se défait
/// d'un tap, et le bandeau du bas fige son chronomètre, ce qui se voit.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.recorder});

  final RideRecorder recorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: recorder.pause,
        icon: const Icon(Icons.pause),
        label: const Text('Mettre en pause', style: TextStyle(fontSize: 15)),
      ),
    );
  }
}

/// Reprendre — et surtout **dire qu'on est en pause**.
///
/// C'est la seule façon de perdre la fin d'une sortie sans s'en apercevoir : les
/// compteurs figés se lisent aussi bien comme « en pause » que comme « à
/// l'arrêt à un feu ». D'où l'aplat orange sur toute la largeur, qui ne laisse
/// aucun doute et qui est en même temps le bouton de reprise.
class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.recorder});

  final RideRecorder recorder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFB35300),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: recorder.resume,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.pause_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enregistrement en pause',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Rien n\'est écrit — la trace reprend où elle s\'est arrêtée.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Icon(Icons.play_arrow, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// La barre des zones, et sa légende.
///
/// Une barre unique plutôt que cinq jauges : ce qu'on cherche à voir, c'est une
/// **proportion** — « j'ai passé la moitié de ma sortie en Z2 » — et une
/// proportion se lit dans une longueur partagée, pas dans cinq longueurs à
/// comparer de tête.
class _ZoneBreakdown extends StatelessWidget {
  const _ZoneBreakdown({
    required this.title,
    required this.shares,
    required this.currentIcon,
    this.current,
  });

  final String title;

  final List<ZoneShare> shares;

  /// La zone où l'on se trouve en ce moment, `null` sans mesure.
  ///
  /// Sa ligne est peinte de sa couleur, tout le long : la légende énumère un
  /// cumul, et sans repère il faut lire le chiffre du bandeau puis retrouver la
  /// ligne correspondante pour savoir où l'on ajoute du temps. L'aplat répond
  /// à la question d'un coup d'œil — « je suis dans celle-là, et ça fait
  /// 12 minutes qu'elle dure ».
  final String? current;

  /// Ce qui remplace la pastille sur la ligne courante : un cœur ou un éclair.
  /// Les deux cartes se ressemblent trait pour trait — c'est cette icône, autant
  /// que le titre, qui dit laquelle on est en train de lire.
  final IconData currentIcon;

  /// Hauteur de la barre. Généreuse : c'est aussi la surface de lecture des
  /// couleurs, et un liseré de 6 pt ne se distingue plus sous la pluie.
  static const _barHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final drawn = [
      for (final share in shares)
        if (share.share > 0) share,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2226),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: _barHeight,
              // Les parts sont converties en poids entiers : un `Expanded` ne
              // prend qu'un `flex` entier, et arrondir au pour mille garde une
              // zone d'une seconde visible sur une sortie de trois heures.
              child: Row(
                children: [
                  for (final share in drawn)
                    Expanded(
                      flex: (share.share * 1000).round().clamp(1, 1000),
                      child: ColoredBox(
                        color: zoneColorOf(share.key) ?? Colors.white24,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Toutes les zones sont listées, y compris celles à zéro : une zone
          // absente de la légende se lirait comme une zone qui n'existe pas,
          // alors que c'est une zone qu'on n'a pas touchée — l'information est
          // exactement l'inverse.
          for (final share in shares)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ZoneLine(
                share: share,
                current: share.key == current,
                currentIcon: currentIcon,
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoneLine extends StatelessWidget {
  const _ZoneLine({
    required this.share,
    required this.currentIcon,
    this.current = false,
  });

  final ZoneShare share;

  /// Celle où l'on se trouve : la ligne passe sur l'aplat de sa zone.
  final bool current;

  final IconData currentIcon;

  @override
  Widget build(BuildContext context) {
    final color = zoneColorOf(share.key) ?? Colors.white24;
    final empty = share.share <= 0;

    // Sur l'aplat, le texte reprend la règle du bandeau — le jaune de Z3 veut
    // du noir, sans quoi c'est justement la zone qu'on surveille qui devient
    // illisible.
    final ink = current
        ? foregroundOf(color)
        : (empty ? Colors.white38 : Colors.white);
    final faded = current
        ? ink.withValues(alpha: 0.8)
        : (empty ? Colors.white38 : Colors.white70);

    // Le rembourrage est le même sur toutes les lignes, peintes ou non : la
    // zone courante change en roulant, et une ligne qui s'élargirait au passage
    // ferait sauter toute la légende sous les yeux.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: current ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // La pastille disparaîtrait dans l'aplat de sa propre couleur : sur la
          // ligne courante, elle cède la place à l'icône, qui dit « c'est ici
          // que ça se passe en ce moment » plutôt que de répéter la couleur.
          SizedBox(
            width: 12,
            height: 12,
            child: current
                ? Icon(currentIcon, size: 12, color: ink)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Text(
            share.key.toUpperCase(),
            style: TextStyle(
              color: ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            formatDuration(share.time),
            style: TextStyle(
              color: ink,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              '${(share.share * 100).round()} %',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: faded,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2226),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}
