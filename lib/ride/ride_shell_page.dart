import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/rider_profile.dart';
import '../account/rider_profile_store.dart';
import '../training/training_budget.dart';
import '../training/training_budget_store.dart';
import '../account/site_session.dart';
import '../ble/samples.dart';
import '../ble/sensor_hub.dart';
import '../dashboard/metric_id.dart';
import '../dashboard/ride_preset.dart';
import '../devices/known_devices_store.dart';
import '../navigation/navigation_picker_sheet.dart';
import '../navigation/navigation_target.dart';
import '../navigation/route_catalog_store.dart';
import '../navigation/screen_dimmer.dart';
import '../phone/phone_sensors.dart';
import '../phone/rider_compass.dart';
import '../recording/ride_recorder.dart';
import '../training_program/training_program.dart';
import '../training_program/training_program_catalog_store.dart';
import '../training_program/workout_lap_series.dart';
import '../training_program/workout_picker_sheet.dart';
import '../ui/offline_download_dialog.dart';
import '../ui/power_calibration_dialog.dart';
import 'auto_return_policy.dart';
import 'battery_alert_sound.dart';
import 'battery_status.dart';
import 'battery_wake_policy.dart';
import 'blocks/bell_player.dart';
import 'climb_alert_sound.dart';
import 'climb_edge_policy.dart';
import 'climb_debug_data.dart';
import 'climb_profile.dart';
import 'di2_button_gesture_policy.dart';
import 'native_turn_alerts.dart';
import 'nav_state.dart';
import 'navigation_web_view.dart';
import 'offline_map_state.dart';
import 'pages/dashboard_page.dart';
import 'radar_alert_sound.dart';
import 'radar_severity.dart';
import 'radar_wake_policy.dart';
import 'reminder_policy.dart';
import 'reminder_wake_policy.dart';
import 'ride_pages.dart';
import 'route_climbs.dart';
import 'route_profile.dart';
import 'screen_policy.dart';
import 'turn_proximity.dart';
import 'workout_cue_player.dart';
import 'workout_policy.dart';
import 'widgets/battery_alert_banner.dart';
import 'widgets/climb_badge.dart';
import 'widgets/compass_badge.dart';
import 'widgets/climb_profile_overlay.dart';
import 'widgets/lap_started_toast.dart';
import 'widgets/map_edge_handle.dart';
import 'widgets/map_swipe_zone.dart';
import 'widgets/notch_band.dart';
import 'widgets/radar_frame.dart';
import 'widgets/radar_side_gauge.dart';
import 'widgets/radar_wake_page.dart';
import 'widgets/reminder_banner.dart';
import 'widgets/ride_bottom_band.dart';
import 'widgets/ride_button_flash.dart';
import 'widgets/ride_page_flash.dart';
import 'widgets/workout_badge.dart';
import 'widgets/workout_change_popup.dart';

/// La coquille d'une sortie : ce qui appartient à l'écran, pas à la page web.
///
/// Elle possède le plein écran, le rétroéclairage, les zones obstruées, le
/// bouton retour et les pages du tableau de bord — **toutes décrites par le
/// profil de sortie** ([RidePreset]) : leur nombre, leur ordre, leur contenu, et
/// jusqu'à la présence d'une carte.
///
/// **Quand le profil a une carte, le WebView reste monté, mesuré et peint en
/// permanence**, au fond d'une pile, et les pages de données glissent par-dessus.
/// Ce n'est pas une commodité de mise en page : une vue plateforme démontée
/// emporte avec elle le pointeur de virage, la progression sur le tracé, l'état
/// de reroutage et les tuiles MapLibre en mémoire — soit un rechargement complet
/// en pleine sortie. Une vue simplement sortie de la liste de peinture, elle, se
/// fait étrangler par certaines surcouches constructeur, et la page cesse de
/// suivre le cycliste. Mesuré sur route avant d'être adopté (sonde M0, branche
/// `m0-webview-probe`) : 465 messages de navigation en sept minutes sous un voile
/// opaque, sans un seul rechargement. **Sa position dans le catalogue n'y change
/// rien** : elle peut être en deuxième page, elle reste au fond de la pile.
///
/// **Quand le profil n'a pas de carte** (home-trainer), le contrôleur n'est ni
/// créé ni chargé : ni pont, ni GPS de page, ni service worker, ni tuiles. Tout
/// ce qui en venait disparaît avec lui — état de navigation, retour automatique,
/// veille demandée par la page. Le garder monté sous des pages opaques coûterait
/// de la batterie pour une carte que personne ne regardera.
class RideShellPage extends StatefulWidget {
  const RideShellPage({
    super.key,
    required this.target,
    required this.preset,
    required this.hub,
    required this.devices,
    required this.recorder,
    this.compass,
    this.phone,
    required this.session,
    required this.riderProfile,
    required this.trainingBudget,
    required this.routes,
    required this.trainingPrograms,
    this.onGridMeasured,
    this.baseUrl = sportsScopeBaseUrl,
  });

  final NavigationTarget target;

  /// Le profil de sortie : les pages, le bandeau, les capteurs, le radar.
  /// Choisi au départ et figé pour la durée de la sortie — changer de tableau
  /// de bord en roulant n'a aucun usage et coûterait de reconstruire la pile.
  final RidePreset preset;

  final SensorHub hub;

  /// Les appareils appairés, pour construire la rangée de batteries — même
  /// magasin que l'accueil (`SensorStatusStrip`), source des lignes du bloc
  /// `battery` (voir `BatteryStatusNotifier`).
  final KnownDevicesStore devices;

  /// Les itinéraires du compte, pour en choisir un autre en pleine sortie. Le
  /// même magasin que l'écran des capteurs : son cache est ce qui rend le choix
  /// possible là où le réseau manque, c'est-à-dire sur la route.
  final RouteCatalogStore routes;

  /// Les programmes d'entraînement du compte, pour en choisir (ou en changer)
  /// sans quitter la sortie — même rôle que [routes], voir `_chooseWorkout`.
  final TrainingProgramCatalogStore trainingPrograms;

  /// L'enregistrement en cours, pour le bandeau et les pages de données. La
  /// coquille ne le pilote pas — il vit au-dessus des écrans et survit à la
  /// navigation.
  final RideRecorder recorder;

  /// La boussole du téléphone. La coquille est la SEULE à l'allumer, et
  /// seulement le temps de la sortie : un magnétomètre branché en permanence
  /// réveille le processeur pour une flèche que personne ne regarde. Nulle sur
  /// un appareil sans magnétomètre, dans un test, ou quand le profil l'a coupée.
  final RiderCompass? compass;

  /// Les capteurs du téléphone lui-même — ici, seulement pour sa batterie
  /// (voir `BatteryStatusNotifier`). Volontairement **pas** tiré de
  /// [compass] : ce dernier est nul dès que le profil coupe la boussole
  /// (`preset.sensors.compass`), et la batterie du téléphone n'a pas de
  /// réglage pour la couper — elle ne doit pas disparaître avec un capteur
  /// sans rapport.
  final PhoneSensors? phone;

  /// Pas pour authentifier la page — le cookie du WebView s'en charge — mais
  /// pour tenir à jour ce que l'appli affiche de la session.
  final SiteSession session;

  /// Seuils et zones du cycliste. La page les récupère du site et les pousse
  /// ici : l'appli n'a aucun identifiant à présenter, elle ne peut pas les
  /// demander elle-même.
  final RiderProfileStore riderProfile;

  /// Le budget de charge du jour. Même chemin que les seuils, et pour la même
  /// raison : c'est la page qui va le chercher, l'appli n'a aucun identifiant à
  /// présenter. Il se périme en revanche, lui, d'où la date qu'il porte.
  final TrainingBudgetStore trainingBudget;

  /// La place qu'une page de grille a réellement eue sur cet écran. Transmise
  /// telle quelle au magasin des profils, qui l'annonce au site au prochain
  /// rafraîchissement : l'éditeur y dimensionne ses aperçus, et supposait
  /// jusque-là un téléphone de référence.
  final ValueChanged<Size>? onGridMeasured;

  final String baseUrl;

  @override
  State<RideShellPage> createState() => _RideShellPageState();
}

class _RideShellPageState extends State<RideShellPage>
    with WidgetsBindingObserver {
  /// Le contrôleur de la page web. **Nul quand le profil n'a pas de carte** :
  /// tout ce qui en dépend est alors conditionné, et le pont n'existe pas.
  NavigationWebController? _web;

  final _screen = ScreenDimmer();
  final _screenPolicy = ScreenPolicy();

  /// Ce que la page dit de la navigation en cours. Alimente le tableau de bord,
  /// et surtout le retour automatique sur la carte à l'approche d'un virage.
  /// Sans carte, personne ne l'alimente jamais — et personne ne l'écoute.
  final _nav = NavStateNotifier();

  /// Le profil du col en cours, résolu depuis [_routeClimbs] par id à chaque
  /// trame `nav` (voir `_onPageMessage`) — donc disponible hors ligne dès que
  /// le tracé est chargé. Sans carte, personne ne l'alimente ni ne l'écoute —
  /// même sort que [_nav].
  final _climbProfile = ClimbProfileNotifier();

  /// Stabilise `nav.climb`, qui peut flickerer d'une trame à l'autre près de
  /// la frontière d'un col (position simulée ou GPS bruité) — voir
  /// [ClimbEdgePolicy]. C'est cet état-là, jamais `_nav.value?.climb` en
  /// direct, qui doit piloter la page col, le tour automatique et le reset du
  /// profil affiché.
  final _climbEdge = ClimbEdgePolicy();

  /// Le col affiché, stabilisé par [_climbEdge] — mis à jour dans
  /// `_onPageMessage` (cas `'nav'`), jamais ailleurs. Pendant le maintien qui
  /// absorbe un flicker de bordure, il garde la dernière valeur non nulle
  /// plutôt que de la perdre : sans ça, la pastille (lue en direct sur `_nav`)
  /// et la page col (lue ici) désynchronisaient — la pastille clignotait avec
  /// le brut pendant que la page retombait sur « Aucun col en cours ».
  final _stableClimb = ValueNotifier<NavClimb?>(null);

  /// La liste des cols du tracé en cours, poussée une fois par tracé (voir
  /// route_climbs.dart). Sans carte, personne ne l'alimente ni ne l'écoute —
  /// même sort que [_nav] et [_climbProfile].
  final _routeClimbs = RouteClimbsNotifier();

  /// Le profil d'altitude du tracé en cours, poussé une fois par tracé (voir
  /// route_profile.dart). Sans carte, personne ne l'alimente ni ne l'écoute —
  /// même sort que [_routeClimbs]. Contrairement à eux,
  /// `AltitudeProfileCard` reste utile même quand cette source est nulle : elle
  /// se rabat alors sur `recorder.elevationTrack`.
  final _routeProfile = RouteProfileNotifier();

  /// La boussole, pour la pastille de la carte — `(cap corrigé, calibrage
  /// vérifié)`, mis à jour une fois par seconde comme [RiderCompass.addFix]
  /// ci-dessous. `null` tant que rien n'est mesurable (pas de magnétomètre,
  /// profil sans boussole, ou aucune trame encore reçue) : la pastille
  /// disparaît alors plutôt que d'offrir un bouton qui ne ferait rien.
  final _compassReading = ValueNotifier<(double, bool)?>(null);

  /// Tap sur la pastille de boussole : force ou relâche sa priorité sur la
  /// course GPS (voir [RiderCompass.forced]). Rien à faire si le profil n'a
  /// pas de boussole — la pastille n'est de toute façon jamais montrée.
  void _toggleCompassForced() {
    final compass = widget.compass;
    if (compass == null) return;
    setState(() => compass.forced = !compass.forced);
    // Le pont n'envoie une mise à jour que si un capteur BLE l'a marqué
    // « sale » entre-temps (`SensorBridge._dirty`) : sans capteur connecté,
    // le nouveau cap ne partirait jamais vers la carte tout seul.
    _web?.bridge.pushNow();
  }

  /// La pastille de col est-elle dépliée en graphique ? Un simple booléen
  /// possédé par la coquille suffit ici — pas de politique séparée comme
  /// [RadarWakePolicy] : il n'y a qu'une seule transition à arbitrer (le tap),
  /// pas d'horloge ni de plusieurs sources concurrentes à départager. Reposée
  /// à [ClimbSettings.expandedByDefault] à chaque nouveau col (voir
  /// `_onPageMessage`, cas `nav`, et `_toggleDebugClimb`) — repliée par
  /// défaut, pour qu'un col qui s'ouvrirait grand tout seul ne recouvre pas la
  /// carte au moment précis où le cycliste a le plus besoin de voir la route
  /// devant lui. Le tap reste libre dans les deux sens quel que soit ce
  /// réglage : lui seul choisit l'état de départ.
  final _climbExpanded = ValueNotifier<bool>(false);

  /// Cherche l'entrée de [_routeClimbs] qui correspond à [id] — voir son
  /// usage dans `_onPageMessage`, cas `'nav'`. `null` sans liste encore reçue,
  /// col sans id (site plus ancien) ou id qui ne matche aucune entrée.
  RouteClimb? _findRouteClimb(int? id) {
    if (id == null) return null;
    for (final climb in _routeClimbs.value?.climbs ?? const <RouteClimb>[]) {
      if (climb.id == id) return climb;
    }
    return null;
  }

  /// Un col de démonstration, affiché par-dessus la sortie réelle — carte,
  /// bandeau, radar, et les pages de données (voir [_debugClimb]) — depuis le
  /// bouton « Simuler un col » du menu d'actions. Juger la pastille et le
  /// graphique dans une vraie sortie, sans attendre de grimper un col, est ce
  /// que la page isolée `ClimbDebugPage` ne permet pas : elle n'a ni carte ni
  /// radar à côté, et surtout aucun enregistrement à qui fermer un tour.
  bool _debugClimbActive = false;

  /// Progresse tout seul une fois activé (voir [_updateDebugClimb]) : de 0 à
  /// 1 en une minute et demie environ. Contrairement à `ClimbDebugPage` (qui
  /// a son propre curseur, pour juger la *composition* à un point fixe), ce
  /// bouton doit aussi pouvoir montrer la **fin** du col — pastille qui
  /// s'éteint, tour fermé tout seul — sans grimper un vrai col ni tripoter un
  /// curseur pendant la sortie.
  double _debugClimbRatio = 0;
  static const _debugClimbStepPerSecond = 1 / 90;

  late final _debugClimbProfile = debugClimbProfile();

  /// Le col de démonstration, sous la forme qu'attendent [ClimbBadge],
  /// [ClimbProfileOverlay] et `ClimbProfileCard` — calculé une fois ici
  /// plutôt qu'à l'identique à chaque endroit qui le consomme.
  NavClimb? get _debugClimb =>
      _debugClimbActive ? debugClimbFor(_debugClimbProfile, _debugClimbRatio) : null;

  void _toggleDebugClimb() {
    if (_debugClimbActive) {
      _endDebugClimb();
      return;
    }
    setState(() {
      _debugClimbActive = true;
      _debugClimbRatio = 0;
    });
    _climbExpanded.value = _preset.climb.expandedByDefault;
    // Même geste qu'un vrai front montant de col (voir ClimbEdgePolicy) :
    // isole la montée dans son propre tour de la série `cols`.
    widget.recorder.markLap(climbLapSeries);
    widget.recorder.tagClimb(climbLapSeries, _debugClimbProfile.id);
  }

  /// Front descendant du col de démonstration, atteint tout seul au sommet
  /// ([_updateDebugClimb]) ou coupé à la main depuis le menu — les deux
  /// doivent fermer le tour, donc partagent ce chemin plutôt que de le
  /// dupliquer.
  void _endDebugClimb() {
    setState(() {
      _debugClimbActive = false;
      _debugClimbRatio = 0;
    });
    _climbExpanded.value = false;
    // Même geste qu'un vrai front descendant : clôt le tour de la montée et
    // en ouvre un nouveau pour la suite.
    widget.recorder.markLap(climbLapSeries);
  }

  /// Appelé par [_tick] : fait grimper le col de démonstration comme s'il
  /// roulait, jusqu'au sommet où il se termine tout seul — voir
  /// [_endDebugClimb].
  void _updateDebugClimb() {
    if (!_debugClimbActive) return;
    final next = _debugClimbRatio + _debugClimbStepPerSecond;
    if (next >= 1) {
      _endDebugClimb();
      return;
    }
    setState(() => _debugClimbRatio = next);
  }

  /// Où en est la carte hors-ligne du tracé affiché. Même sort que [_nav] :
  /// sans carte, personne ne l'alimente ni ne l'écoute.
  final _offline = OfflineMapNotifier();

  /// Le téléchargement demandé par [NavigationTarget.autoDownloadOffline] a-t-il
  /// déjà été lancé ? Sans ce verrou, chaque nouveau message `'offline'` du pont
  /// (il en arrive à chaque changement d'état) retenterait le téléchargement.
  bool _autoOfflineTriggered = false;

  late final PageController _pages;

  /// L'index brut du défilement, qui monte et descend sans borne pour que le
  /// catalogue tourne en boucle (voir [rawPageOriginFor]).
  late int _rawPage;

  RidePreset get _preset => widget.preset;

  /// Le défilement et le menu, tels que le profil les décrit **structurel-
  /// lement** — calculés au montage et non à chaque trame, comme le profil lui-
  /// même. Une page qui porte une condition (voir [_conditionalPages]) reste
  /// classée ici côté menu : c'est [_activeConditional] qui, en roulant, la
  /// fait apparaître dans [_ridePages].
  late final List<RidePageSpec> _baseRidePages;
  late final List<RidePageSpec> _baseMenuPages;

  /// Les pages du menu qui portent une condition de sortie — sous-ensemble de
  /// [_baseMenuPages]. Vide pour l'immense majorité des profils, qui n'en
  /// posent aucune : [_updateConditionalPages] sort alors tout de suite.
  late final List<RidePageSpec> _conditionalPages;

  /// Les pages conditionnelles actuellement actives — réévaluées à chaque tic
  /// (voir [_updateConditionalPages]), jamais à chaque trame : ni [NavState] ni
  /// la pente ne changent plus vite que la seconde qui sépare deux tics.
  Set<RidePageSpec> _activeConditional = const {};

  /// Les pages du défilement rangées à la main, depuis leur propre menu ⋮
  /// (« Masquer cette page », voir [_hidePage]). Un geste de l'instant, jamais
  /// écrit sur le profil : reparti de zéro au prochain lancement, même sortie
  /// ou non, [_baseRidePages] repart telles que le site les décrit.
  Set<RidePageSpec> _manuallyHidden = const {};

  /// Les pages du menu rejointes au défilement à la main, depuis le menu ⋮ de
  /// la page ouverte (« Afficher dans le défilement », voir [_showPage]).
  /// Symétrique de [_manuallyHidden] : un geste de l'instant, jamais écrit sur
  /// le profil. Une page qu'un [PageMenuCondition] a fait rejoindre le
  /// défilement n'y figure pas — c'est [_activeConditional] qui la porte, et
  /// [_ridePages] se garde de l'ajouter deux fois.
  Set<RidePageSpec> _manuallyShown = const {};

  /// Les pages conditionnelles **actives** rangées à la main malgré leur
  /// condition — depuis leur propre menu ⋮, exactement comme
  /// [_manuallyHidden], mais il fallait un ensemble à part : une page dont la
  /// condition tient n'est jamais dans [_baseRidePages], donc y entrer ne
  /// suffirait pas à la retirer du défilement, [_activeConditional] la
  /// remettant aussitôt. Purgée dès que la condition cesse de tenir (voir
  /// [_updateConditionalPages]) — masquer un col en cours ne doit pas
  /// escamoter le suivant, sans quoi le geste se lirait « plus jamais cette
  /// page » alors que le cycliste n'a voulu dire que « pas celui-ci ».
  Set<RidePageSpec> _manuallyHiddenConditional = const {};

  /// Le défilement du moment : les pages toujours-défilantes non masquées à la
  /// main, puis les pages conditionnelles actives et non masquées à la main,
  /// **toujours en fin de liste**. Cet ordre garde la carte et les pages qui
  /// la précèdent à un index stable tant que rien n'est masqué — [_mapPage] se
  /// recalcule quand même à chaque accès, parce qu'une page masquée avant elle
  /// décale bel et bien tout ce qui suit.
  List<RidePageSpec> get _ridePages => [
        for (final page in _baseRidePages)
          if (!_manuallyHidden.contains(page)) page,
        for (final page in _conditionalPages)
          if (_activeConditional.contains(page) &&
              !_manuallyHiddenConditional.contains(page))
            page,
        for (final page in _baseMenuPages)
          if (_manuallyShown.contains(page) &&
              !(_conditionalPages.contains(page) && _activeConditional.contains(page)))
            page,
      ];

  /// Les pages rangées derrière le menu du moment : celles masquées à la main,
  /// les pages sans condition et non rejointes à la main, les pages
  /// conditionnelles **inactives**, et les pages conditionnelles actives mais
  /// masquées à la main — une page active et non masquée est dans
  /// [_ridePages], pas ici, elle n'a donc pas besoin d'être allée chercher.
  List<RidePageSpec> get _menuPages => [
        for (final page in _baseMenuPages)
          if (!_manuallyShown.contains(page) &&
              (!_conditionalPages.contains(page) ||
                  !_activeConditional.contains(page) ||
                  _manuallyHiddenConditional.contains(page)))
            page,
        for (final page in _baseRidePages)
          if (_manuallyHidden.contains(page)) page,
      ];

  /// La page ouverte depuis le menu, index dans [_menuPages]. `null` la plupart
  /// du temps — c'est une page qu'on va chercher, pas une page où l'on est.
  int? _menuPage;

  int get _pageCount => _ridePages.length;

  /// La page affichée, index dans le défilement.
  int get _page => pageOf(_rawPage, count: _pageCount);

  /// Où est la carte dans le défilement, `null` quand le profil n'en a pas.
  ///
  /// Recalculé sur [_ridePages] et non pris tel quel sur
  /// [RidePreset.mapPageIndex] : une page masquée à la main avant la carte
  /// (voir [_hidePage]) décale son index, contrairement aux pages
  /// conditionnelles, toujours ajoutées en fin de liste.
  int? get _mapPage {
    final pages = _ridePages;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i] is MapPageSpec) return i;
    }
    return null;
  }

  /// La carte est-elle sous les yeux ?
  ///
  /// **Une page du menu par-dessus suffit à répondre non**, et c'est le point de
  /// passage obligé : occlusion de la page web, rétroéclairage, bandes de
  /// changement de page et physique du défilement lisent tous ce prédicat. Sans
  /// le voile ici, la carte continuerait d'animer sous une page opaque, et les
  /// bandes des bords feraient défiler ce qu'on ne voit pas.
  bool get _onMap => _menuPage == null && _mapPage != null && _page == _mapPage;

  /// L'habillage radar plein écran est-il posé ? Le capteur coupé le retire
  /// aussi : sans trame, la jauge et le cadre ne dessinent déjà rien, et le
  /// test évite de monter trois écouteurs pour rien.
  bool get _overlay => _preset.radar.overlay && _preset.sensors.radar;

  /// Le retour automatique sur la carte, et la restitution de la page ensuite.
  final _alerts = RideAlertSource();
  // Pas `final` : [_hidePage]/[_showPage] la reconstruisent quand masquer une
  // page décale l'index de la carte, `mapPage` n'ayant pas d'autre façon
  // d'être corrigé après coup. Le rare vol d'alerte en cours à cet instant
  // précis se contente de reperdre la page qu'il devait rendre — un geste
  // volontaire du menu, jamais aussi pressant qu'un virage.
  late AutoReturnPolicy _autoReturn;
  static const _proximity = TurnProximity();

  /// Filet natif de virages, voir `native_turn_alerts.dart`. `null` tant que le
  /// tracé n'a pas de jeton (reprise, navigation libre) ou que la récupération
  /// n'a pas encore répondu.
  NativeTurnAlerts? _nativeTurns;

  /// Le bip du filet natif — voir `native_turn_alerts.dart`. Chargé d'avance
  /// dans [_loadNativeTurnAlerts], en même temps que les virages.
  final _nativeTurnSound = NativeTurnAlertSound();

  /// L'horloge du retour automatique. Le front d'une alerte arrive par le pont,
  /// mais « rendre la page une fois le calme revenu » n'est piloté que par le
  /// temps qui passe.
  Timer? _tick;

  /// Boutons distants (D-Fly du Di2) — voir `RemoteButtonSample`
  /// (`ble/samples.dart`) pour le canal brut, [Di2ButtonGesturePolicy] pour
  /// sa classification en clic/double-clic/appui long, et
  /// [_performButtonAction] pour l'exécution.
  StreamSubscription<SensorSample>? _remoteButtonSub;

  /// Tic dédié à [Di2ButtonGesturePolicy.resolve], plus rapide que celui d'une
  /// seconde qui pilote le reste de la coquille : l'appui long se déclenche
  /// entre deux trames de maintien (répétées à ~1 s d'écart), et un tic à
  /// 1 Hz ferait attendre jusqu'à la trame suivante — près d'une seconde de
  /// retard en plus du seuil lui-même — avant de le voir. Séparé plutôt que
  /// fondu dans `_tick` : accélérer *tout* le reste (retour auto, réveil
  /// radar) n'a aucune raison d'accompagner ce seul réglage.
  Timer? _buttonTick;
  final _buttonGestures = Di2ButtonGesturePolicy();

  /// Tic dédié à la boussole, plus rapide que celui d'une seconde. Il rafraîchit
  /// la pastille et, **quand le cap est forcé** (pastille verrouillée), pousse
  /// le cap à la page : la carte du site doit alors tourner en direct sous le
  /// doigt qui oriente le téléphone, pas par à-coups d'une seconde. Séparé de
  /// `_tick` parce que `compass.addFix` doit rester à 1 Hz — l'appeler à 5 Hz
  /// injecterait cinq fois le même fix dans le calibrage — et séparé de
  /// `_buttonTick`, qui n'existe que si le profil garde les boutons Di2.
  Timer? _compassTick;

  /// La sonnette/le klaxon déclenchés par un geste de bouton distant —
  /// indépendante de tout [BellControl] posé sur le tableau de bord, comme
  /// deux `BellControl` le seraient déjà entre eux.
  final _buttonBell = BellPlayer();

  /// Le dernier geste de bouton résolu, pour [RideButtonFlash] — `seq`
  /// incrémenté à chaque geste, y compris deux fois le même de suite, sinon
  /// le second ne changerait rien à l'œil du widget et ne s'afficherait pas.
  ButtonGestureFlash? _buttonFlash;
  int _buttonFlashSeq = 0;

  /// Le cycliste a-t-il changé de page de sa main depuis la dernière décision ?
  bool _userMoved = false;

  /// L'état retenu de la condition `descending`, avec hystérésis — voir
  /// [_conditionMet]. Seule des trois conditions à porter sur un échantillon
  /// brut plutôt qu'un état déjà poussé par la page (`onRoute`, `climb`) : sans
  /// bande morte, la page basculerait dedans et dehors à chaque tic autour du
  /// seuil.
  bool _descending = false;

  /// L'alerte vue au tic précédent — pour ne fermer la page du menu qu'au
  /// **front montant**, voir [_decideReturn].
  RideAlert _lastAlert = RideAlert.none;

  /// Nombre de déplacements en cours décidés par la politique. Un compteur et
  /// pas un booléen : deux animations peuvent se chevaucher.
  int _autoMoves = 0;

  /// La source radar effectivement écoutée.
  ///
  /// Quand le profil coupe le radar, c'est un notifieur **muet** plutôt qu'une
  /// grappe de conditions dans tout le fichier : le cadre, les gouttières, les
  /// mètres, le son et le réveil lisent alors tous « absent », qui est
  /// exactement ce qu'il faut afficher — et jamais « voie libre ».
  late final ValueNotifier<RadarSample?> _mutedRadar;
  late final RadarViewNotifier _radar;

  /// Et sa voix : le seul élément du tableau de bord qui n'attende pas qu'on
  /// regarde l'écran.
  final _radarVoice = RadarAlertVoice();
  final _radarSound = RadarAlertPlayer();

  /// Les tonalités de début et de fin de col — voir [ClimbEdgePolicy]
  /// (_climbEdge, plus bas) pour le front qui les déclenche.
  final _climbSound = ClimbAlertPlayer();

  /// Ce qui décide de rallumer l'écran pour une voiture, et de le rendre à la
  /// veille ensuite.
  late final RadarWakePolicy _radarWake;

  /// La batterie de chaque appareil connu, et sa voix — mêmes principes que
  /// le radar, mais jamais coupée par le profil (voir
  /// `SensorSettings.allows(SensorKind.battery)`).
  late final BatteryStatusNotifier _battery;
  final _batteryVoice = BatteryAlertVoice();
  final _batterySound = BatteryAlertPlayer();

  /// Ce qui décide de rallumer l'écran pour une alerte batterie, et de le
  /// rendre à la veille ensuite — impulsion plutôt qu'état continu, voir
  /// `BatteryWakePolicy`.
  late final BatteryWakePolicy _batteryWake;

  /// Les appareils à nommer dans le bandeau d'alerte, vide = rien à montrer.
  /// Partage l'horloge de [_batteryWake] : pas de minuteur séparé pour le
  /// bandeau, voir `_updateBatteryWake`.
  final _batteryAlert = ValueNotifier<List<BatteryStatus>>(const []);

  /// Les rappels périodiques du profil (boire, manger, entamer une
  /// intervalle), et ce qui décide quand ils tombent — voir
  /// `RideReminderPolicy`. Construite dans `initState` : elle a besoin du
  /// temps déjà roulé pour ne pas rejouer le dernier rappel sonné avant un
  /// aller-retour à l'accueil, la coquille se démontant et se remontant à
  /// chaque fois.
  late final RideReminderPolicy _reminderPolicy;

  /// Ce qui décide de rallumer l'écran pour un rappel, et de le rendre à la
  /// veille ensuite — impulsion plutôt qu'état continu, même famille que
  /// [_batteryWake].
  final _reminderWake = ReminderWakePolicy();

  /// Instance à part de [_buttonBell] et de tout `BellControl` posé sur le
  /// tableau de bord : un rappel n'a pas de widget à lui, même raison que
  /// `RingBellAction` garde la sienne.
  final _reminderBell = BellPlayer();

  /// Les rappels tombés au tic courant, vide = rien à montrer — même patron
  /// que [_batteryAlert].
  final _reminderAlert = ValueNotifier<List<ReminderSpec>>(const []);

  /// Ce qui décide quel jalon d'un programme d'entraînement vient d'être
  /// franchi — `null` tant qu'aucun n'est actif. Reconstruite (pas juste
  /// lue) à chaque changement de `widget.recorder.activeWorkout`, voir
  /// `_updateWorkout`.
  WorkoutPolicy? _workoutPolicy;

  /// Le programme sur lequel [_workoutPolicy] a été construite — sert à
  /// détecter qu'il a changé (nouvelle activation, ou détaché) sans
  /// s'abonner à `widget.recorder` en plus du tic déjà en place partout
  /// ailleurs dans cette coquille.
  TrainingProgram? _workoutProgram;

  /// Ce qui décide quand lancer le son d'un jalon — décalé plus tôt que son
  /// franchissement (voir `WorkoutCuePolicy`), donc un curseur distinct de
  /// [_workoutPolicy] bien que reconstruit aux mêmes instants.
  WorkoutCuePolicy? _workoutCuePolicy;

  /// Les sons des jalons — même patron que [_climbSound], contexte audio
  /// « duck » plutôt que le flux alarme de [_reminderBell] : un programme
  /// peut sonner toutes les 30 secondes, bien plus intrusif à couper la
  /// musique à chaque fois qu'un col ou un rappel, tous deux rares par
  /// comparaison.
  final _workoutCue = WorkoutCuePlayer();

  /// Le jalon dont le popup de changement est à l'écran, `null` = rien à
  /// montrer — même patron que [_batteryAlert]/[_reminderAlert], mais un
  /// minuteur propre plutôt que la veille d'écran : ce popup s'efface après
  /// un délai fixe, il ne tient pas d'état « éveillé/rendormi » comme les
  /// alertes batterie/rappel.
  final _workoutChangeAlert = ValueNotifier<WorkoutMilestone?>(null);

  /// Combien de temps le popup reste affiché avant de s'effacer tout seul.
  static const _workoutChangeDuration = Duration(seconds: 3);

  Timer? _workoutChangeTimer;

  /// Le nom du tour dont le toast est à l'écran, `null` = rien à montrer —
  /// même patron que [_workoutChangeAlert], sur un événement distinct
  /// ([RideRecorder.lapStarted]) : voir [_onLapStarted].
  final _lapToast = ValueNotifier<String?>(null);

  /// Même délai que [_workoutChangeDuration] : assez long pour se lire d'un
  /// coup d'œil, assez court pour ne pas s'attarder sur un tour déjà en cours.
  static const _lapToastDuration = Duration(seconds: 3);

  Timer? _lapToastTimer;

  late final MetricSources _sources;

  /// Construit une fois : un changement de page ne doit pas reconstruire l'arbre
  /// du WebView.
  Widget? _webView;

  @override
  void initState() {
    super.initState();

    // Plein écran, barres système comprises : sur un guidon, chaque centimètre
    // de carte compte. `sticky` les fait réapparaître le temps d'un balayage
    // depuis le bord puis les remasque.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);

    _baseRidePages = _preset.ridePages;
    _baseMenuPages = _preset.menuPages;
    _conditionalPages = [
      for (final page in _baseMenuPages)
        if (page.menuCondition != null) page,
    ];

    _rawPage = rawPageOriginFor(_pageCount);
    _pages = PageController(initialPage: _rawPage);

    _autoReturn = AutoReturnPolicy(mapPage: _mapPage);
    _radarWake = RadarWakePolicy(hold: _preset.radar.wakeHold);
    _batteryWake = BatteryWakePolicy();
    _reminderPolicy = RideReminderPolicy(
      reminders: _preset.reminders,
      recorded: widget.recorder.recorded,
    );

    // Comme `_reminderPolicy` : si un programme est déjà actif au montage
    // (démontage/remontage en pleine sortie), on le seede sur l'écoulé réel
    // pour ne pas rejouer ses jalons déjà franchis. `_updateWorkout` peut
    // alors supposer que tout changement qu'il observe ensuite est une
    // activation en direct — jamais un remontage — et seeder à zéro sans y
    // repenser (voir le commentaire là-bas).
    _workoutProgram = widget.recorder.activeWorkout;
    final workoutProgram = _workoutProgram;
    final workoutElapsed = widget.recorder.workoutElapsed ?? Duration.zero;
    _workoutPolicy = workoutProgram == null
        ? null
        : WorkoutPolicy(milestones: workoutProgram.milestones, elapsed: workoutElapsed);
    _workoutCuePolicy = workoutProgram == null
        ? null
        : WorkoutCuePolicy(
            milestones: workoutProgram.milestones,
            soundDuration: _workoutCue.durationOf,
            elapsed: workoutElapsed,
          );

    _mutedRadar = ValueNotifier<RadarSample?>(null);
    _radar = RadarViewNotifier(
      _preset.sensors.radar ? widget.hub.latestRadar : _mutedRadar,
      closeM: _preset.radar.closeM,
      rangeM: _preset.radar.rangeM,
    );
    _radar.addListener(_onRadar);
    // Chargés maintenant : quand une voiture arrivera, il ne sera plus temps
    // d'ouvrir des fichiers. Inutile si le profil coupe le son.
    if (_preset.radar.sounds && _preset.sensors.radar) {
      unawaited(_radarSound.warmUp());
    }
    // Contrairement au radar/à la batterie, aucune éligibilité à vérifier au-
    // delà du réglage de profil lui-même : un programme peut être choisi à
    // tout moment de la sortie (menu ⋮), pas seulement au départ.
    if (_preset.workout.sounds) {
      unawaited(_workoutCue.warmUp());
    }
    // Un col n'existe que sur une carte (voir `NavState.climb`) : sans elle,
    // le front ne se produira jamais et il n'y a rien à charger d'avance.
    if (_preset.climb.sounds && _preset.hasMap) {
      unawaited(_climbSound.warmUp());
    }

    _battery = BatteryStatusNotifier(
      widget.devices,
      widget.hub,
      phone: widget.phone,
      thresholdPercent: _preset.battery.thresholdPercent,
    );
    _battery.addListener(_onBatteryStatus);
    if (_preset.battery.sounds) unawaited(_batterySound.warmUp());

    // Même garde que pour le radar : un profil qui écarte le Di2 (vélo prêté,
    // boîtier de l'autre vélo) ne doit pas laisser ses boutons piloter le
    // tableau de bord. `_stepPage` marque déjà le geste comme manuel
    // (`_autoMoves == 0` dans `_onPageChanged`), donc une pression suspend le
    // retour auto exactement comme un glissé de bandeau.
    if (_preset.sensors.gears) {
      _remoteButtonSub = widget.hub.samples.listen((sample) {
        if (sample is! RemoteButtonSample) return;
        if (_buttonGestures.onPress(sample.channel, sample.at, sample.pressKind)
            case final gesture?) {
          _dispatchButtonGesture(sample.channel, gesture);
        }
      });
      _buttonTick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        for (final event in _buttonGestures.resolve(DateTime.now())) {
          _dispatchButtonGesture(event.channel, event.gesture);
        }
      });
    }

    // La boussole ne sert qu'avec une carte — c'est la page qui consomme le cap
    // — et ne mesure rien tant qu'on n'a pas comparé ses caps à la course GPS.
    if (_preset.sensors.compass && _preset.hasMap) {
      widget.compass?.start();
      _compassTick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final compass = widget.compass;
        if (compass == null) return;
        final heading = compass.correctedHeadingDeg;
        _compassReading.value =
            heading == null ? null : (heading, compass.isTrusted);
        // Le pont ne se marque « sale » tout seul que sur une trame BLE : sans
        // ce push, le cap forcé resterait figé sur la valeur du tap et la
        // flèche de la carte ne suivrait pas la boussole qui continue de
        // tourner.
        if (compass.forced) _web?.bridge.pushNow();
      });
    }

    if (_preset.hasMap) {
      _web = NavigationWebController(
        hub: widget.hub,
        compass: _preset.sensors.compass ? widget.compass : null,
        recorder: widget.recorder,
        traveledPath: _preset.traveledPath,
        target: widget.target,
        baseUrl: widget.baseUrl,
        onMessage: _onPageMessage,
        onPageFinished: _onPageFinished,
      );
      _webView = NavigationWebView(controller: _web!);
      unawaited(_nativeTurnSound.warmUp());
      unawaited(_loadNativeTurnAlerts(widget.target));
    }

    _sources = MetricSources(
      hub: widget.hub,
      recorder: widget.recorder,
      riderProfile: widget.riderProfile,
      trainingBudget: widget.trainingBudget,
      drivetrain: widget.recorder.drivetrain,
      // Sans carte, aucune page ne publiera d'état : les mesures qui en
      // dépendent s'abstiennent au lieu d'attendre pour toujours.
      nav: _preset.hasMap ? _nav : null,
      routeClimbs: _preset.hasMap ? _routeClimbs : null,
      climb: _preset.hasMap ? _stableClimb : null,
      upcomingClimb: _preset.hasMap ? _upcomingClimb : null,
      climbProfile: _preset.hasMap ? _climbProfile : null,
      routeProfile: _preset.hasMap ? _routeProfile : null,
    );

    // Deux déclencheurs pour une seule décision : le pont pour les fronts, le
    // temps pour les délais. Le tic sert aussi au maintien du réveil radar.
    _nav.addListener(_decideReturn);
    widget.recorder.lapStarted.addListener(_onLapStarted);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _decideReturn();
      _updateRadarWake();
      _updateBatteryWake();
      _updateReminders();
      _updateWorkout();
      _updateDebugClimb();
      _checkNativeTurnAlert();
      // Avant _updateConditionalPages, qui en dépend via _nearCol.
      _updateUpcomingClimb();
      _updateConditionalPages();
      // Boutons distants : voir `_buttonTick`, plus rapide, pour
      // `Di2ButtonGesturePolicy.resolve`.
      // Même source que le chien de garde (`recorder.lastFix`) et même
      // conséquence assumée : hors enregistrement la boussole n'a aucune course
      // à laquelle se comparer, donc elle ne se validera pas. Reste à 1 Hz
      // (cadence des fix GPS) : le rafraîchissement de la pastille et le push
      // du cap forcé, eux, sont sur `_compassTick`, plus rapide.
      widget.compass?.addFix(widget.recorder.lastFix);
    });
  }

  void _onPageFinished() {
    _publishInsets();
    // Une page fraîchement chargée n'est pas en veille : son voile noir a
    // disparu avec son état. Sans cette remise à zéro, un rechargement en
    // pleine veille laisserait une carte allumée à 1 % de luminosité.
    _applyScreen(_screenPolicy.pageReloaded());
    // Elle ne sait pas non plus qu'elle est peut-être masquée par une page de
    // données : on le lui redit, sinon elle animerait dans le vide.
    _web?.setOccluded(!_onMap);
    // Elle a pu recharger, ou ouvrir un autre tracé : l'arrivée qu'on avait déjà
    // vue ne compte plus.
    _alerts.reset();
    _autoReturn.reset();
    // Idem pour le front de fermeture de la page du menu : un virage encore
    // proche juste après le rechargement doit se relire comme une alerte
    // neuve, pas comme la suite de celle d'avant.
    _lastAlert = RideAlert.none;
    _checkSession();
  }

  /// Le radar vient de changer d'état : y a-t-il quelque chose à dire, et
  /// quelque chose à montrer ?
  void _onRadar() {
    final cue = _radarVoice.read(_radar.value.severity);
    // La voix est lue dans tous les cas, y compris muette : c'est elle qui tient
    // le front des escalades, et la sauter ferait annoncer d'un coup toutes les
    // voitures accumulées le jour où le son revient.
    if (cue != null && _preset.radar.sounds) _radarSound.play(cue);
    _updateRadarWake();
  }

  /// Rallumer l'écran pour une voiture, et le rendre à la veille ensuite.
  void _updateRadarWake() {
    if (!mounted) return;
    if (!_preset.radar.wakeScreen) return;

    final changed = _radarWake.update(
      now: DateTime.now(),
      alerting: _radar.value.isAlerting,
    );
    if (!changed) return;

    _applyScreen(_screenPolicy.radarAwake(_radarWake.awake));
  }

  /// Une batterie vient de franchir le seuil du profil à la baisse : y a-t-il
  /// quelque chose à dire, et quelque chose à montrer ?
  void _onBatteryStatus() {
    final lowered = _batteryVoice.read(_battery.value);
    if (lowered.isEmpty) return;

    // Un seul son même si plusieurs appareils franchissent le seuil au même
    // tic — pas une cacophonie au démarrage.
    if (_preset.battery.sounds) _batterySound.play();

    _batteryAlert.value = lowered;
    // `trigger` rend vrai seulement sur le front veille → réveil : une
    // deuxième alerte pendant le maintien prolonge le réveil sans le
    // redemander à `ScreenPolicy`.
    if (_batteryWake.trigger(DateTime.now())) {
      _applyScreen(_screenPolicy.batteryAwake(true));
    }
  }

  /// Referme le réveil batterie une fois le maintien passé, et vide le
  /// bandeau avec lui : les deux partagent la même horloge, pas de minuteur
  /// séparé pour l'un ou l'autre.
  void _updateBatteryWake() {
    if (!mounted) return;

    final changed = _batteryWake.update(DateTime.now());
    if (!changed) return;

    _applyScreen(_screenPolicy.batteryAwake(_batteryWake.awake));
    _batteryAlert.value = const [];
  }

  /// À chaque tic : un intervalle du profil vient-il de s'écouler, et faut-il
  /// refermer le réveil d'écran du dernier rappel tombé ?
  void _updateReminders() {
    if (!mounted) return;

    final due = _reminderPolicy.read(widget.recorder.recorded);
    if (due.isNotEmpty) {
      // Un seul son même si deux intervalles tombent au même tic — celui du
      // premier rappel du profil, pas une cacophonie au démarrage.
      unawaited(_reminderBell.start(due.first.sound));
      _reminderAlert.value = due;
      // `trigger` rend vrai seulement sur le front veille → réveil : un
      // second rappel pendant le maintien le prolonge sans le redemander à
      // `ScreenPolicy`.
      if (_reminderWake.trigger(DateTime.now())) {
        _applyScreen(_screenPolicy.reminderAwake(true));
      }
    }

    final changed = _reminderWake.update(DateTime.now());
    if (!changed) return;

    _applyScreen(_screenPolicy.reminderAwake(_reminderWake.awake));
    _reminderAlert.value = const [];
  }

  /// À chaque tic : le programme actif a-t-il changé ? Le seul cas où ça
  /// arrive ici, c'est une nouvelle activation en direct (menu ⋮) — un
  /// programme déjà en cours au montage de la coquille (remontage) est déjà
  /// pris en compte dans `initState`, qui seede alors sur l'écoulé réel pour
  /// ne pas rejouer les jalons déjà franchis. Une activation en direct, elle,
  /// seede toujours à zéro : rien n'a encore pu être franchi. Seeder plutôt
  /// sur `workoutElapsed` ici serait racy — son horloge (le timer du
  /// [RideRecorder]) tourne indépendamment de celle de ce tic, `elapsed`
  /// pourrait donc déjà valoir 1s ou plus au moment de cette reconstruction,
  /// assez pour que le jalon d'ouverture (toujours à l'offset 0) soit
  /// considéré à tort comme déjà franchi et ne sonne jamais.
  ///
  /// Gardé sur `isActive` comme [RideRecorder.markLap] : `workoutElapsed`
  /// n'avance que pendant l'enregistrement, donc un programme attaché avant
  /// le départ ne perd rien — son premier jalon se déclenche dès que
  /// l'enregistrement démarre réellement, sans distinguer les deux cas.
  void _updateWorkout() {
    if (!mounted) return;

    final program = widget.recorder.activeWorkout;
    if (program != _workoutProgram) {
      _workoutProgram = program;
      _workoutPolicy = program == null
          ? null
          : WorkoutPolicy(milestones: program.milestones, elapsed: Duration.zero);
      _workoutCuePolicy = program == null
          ? null
          : WorkoutCuePolicy(
              milestones: program.milestones,
              soundDuration: _workoutCue.durationOf,
              elapsed: Duration.zero,
            );
    }

    final elapsed = widget.recorder.workoutElapsed;
    if (elapsed == null || !widget.recorder.isActive) return;

    // Lu avant le franchissement lui-même : c'est ce qui fait démarrer le
    // son en avance sur l'offset qu'il annonce.
    final cue = _workoutCuePolicy?.read(elapsed);
    if (_preset.workout.sounds && cue?.sound != null) _workoutCue.play(cue!.sound!);

    final milestone = _workoutPolicy?.read(elapsed);
    if (milestone == null) return;
    widget.recorder.markLap(workoutLapSeries, label: milestone.segmentName);
    if (_preset.workout.popup) _showWorkoutChangePopup(milestone);
  }

  /// Affiche le popup de changement de tronçon, et programme son effacement.
  /// Un nouveau jalon avant l'échéance annule le minuteur précédent plutôt
  /// que d'empiler deux effacements : c'est toujours le dernier tronçon
  /// entré qui doit rester affiché [_workoutChangeDuration].
  void _showWorkoutChangePopup(WorkoutMilestone milestone) {
    _workoutChangeTimer?.cancel();
    _workoutChangeAlert.value = milestone;
    _workoutChangeTimer = Timer(_workoutChangeDuration, () {
      if (!mounted) return;
      _workoutChangeAlert.value = null;
    });
  }

  /// [RideRecorder.lapStarted] couvre toutes les séries — manuelle
  /// (bandeau/encoche/page), Di2, col et entraînement. La série `workout` en
  /// est écartée ici plutôt que côté [RideRecorder] : elle a déjà sa propre
  /// annonce ([_showWorkoutChangePopup], réglage [WorkoutSettings.popup]), un
  /// second toast au même instant ferait doublon.
  void _onLapStarted() {
    final event = widget.recorder.lapStarted.value;
    if (event == null || event.series == workoutLapSeries) return;
    if (!_preset.laps.toast) return;
    final label = event.label?.isNotEmpty == true ? event.label! : 'Tour ${event.index + 1}';
    _lapToastTimer?.cancel();
    _lapToast.value = label;
    _lapToastTimer = Timer(_lapToastDuration, () {
      if (!mounted) return;
      _lapToast.value = null;
    });
  }

  /// Faut-il ramener le cycliste sur la carte, ou lui rendre sa page ?
  ///
  /// Sans carte dans le profil, [AutoReturnPolicy] est inerte et rend toujours
  /// « rester » : il n'y a pas de page web, donc pas de virage à annoncer.
  void _decideReturn() {
    if (!mounted) return;

    final now = DateTime.now();
    final state = _nav.value;
    final alert = _alerts.read(
      state,
      turnImminent: _proximity.imminent(
        state: state,
        fix: widget.recorder.lastFix,
        now: now,
      ),
    );

    // La veille de la page web se réveille toute seule à l'approche d'un
    // virage — c'est elle qui l'a vu venir.
    //
    // Une alerte referme la page du menu, **avant** que la politique ne décide.
    //
    // Deux raisons, et la seconde est la plus fourbe : d'abord une page opaque
    // en travers de la carte est exactement ce qu'un virage vient chercher.
    // Ensuite, la politique juge sur `currentPage` : la page ouverte n'en est
    // pas une, si bien qu'un virage annoncé alors qu'on lit son bilan au-dessus
    // de la carte se serait lu « il est déjà sur la carte, rien à faire » — et
    // le cycliste aurait manqué le virage devant un tableau de chiffres.
    //
    // **Seulement au front montant.** `RideAlert.turn` et `offRoute` sont des
    // niveaux, pas des impulsions (voir `RideAlertSource`) : sur `!=
    // RideAlert.none` tout court, ce tic tournant chaque seconde refermait la
    // page du menu qu'on venait d'ouvrir, tant que le virage restait « proche »
    // — le cycliste ne pouvait plus jamais consulter un bilan tant qu'une
    // alerte durait.
    final alertRising = alert != RideAlert.none && _lastAlert == RideAlert.none;
    _lastAlert = alert;
    if (alertRising) _setMenuPage(null);

    final decision = _autoReturn.update(
      now: now,
      currentPage: _page,
      alert: alert,
      userMoved: _userMoved,
    );
    _userMoved = false;

    if (decision.goTo case final page?) _goToPage(page, auto: true);
  }

  /// Fait rejoindre le défilement aux pages du menu dont la condition vient de
  /// se vérifier, et en ressort celles dont la condition vient de cesser.
  ///
  /// Appelée au même tic que [_decideReturn] : ni [NavState] ni la pente ne
  /// changent plus vite que la seconde qui les sépare, pas besoin d'un
  /// écouteur de plus.
  void _updateConditionalPages() {
    if (_conditionalPages.isEmpty) return;

    final next = <RidePageSpec>{
      for (final page in _conditionalPages)
        if (_conditionMet(page)) page,
    };
    final unchanged = next.length == _activeConditional.length &&
        next.every(_activeConditional.contains);
    if (unchanged) return;

    // Une page du menu ouverte referme d'abord : ses indices dans [_menuPages]
    // ne veulent plus rien dire une fois l'ensemble actif changé.
    _setMenuPage(null);

    // Capturée **avant** la mutation : c'est l'identité de la page regardée,
    // pas son index, qui doit survivre à la recomposition.
    final currentSpec = _pageCount > 0 ? _ridePages[_page] : null;
    // La première dans l'ordre du profil s'il y en a plusieurs — même
    // arbitrage que partout ailleurs dans ce contrat (la première règle
    // cohérente gagne).
    RidePageSpec? autoOpen;
    for (final page in _conditionalPages) {
      if (next.contains(page) && !_activeConditional.contains(page) && page.menuAutoOpen) {
        autoOpen = page;
        break;
      }
    }

    setState(() {
      _activeConditional = next;
      // Une page dont la condition vient de retomber n'a plus de raison de
      // rester dans cet ensemble : la laisser trainer la marquerait « masquée
      // à la main » pour la prochaine fois que la condition se vérifiera, ce
      // que le geste qui l'a masquée ne voulait pas dire.
      if (_manuallyHiddenConditional.isNotEmpty) {
        _manuallyHiddenConditional = _manuallyHiddenConditional.intersection(next);
      }
    });

    // Une alerte en cours possède l'écran (voir [_decideReturn], appelé juste
    // avant sur ce même tic, qui vient de fixer [_lastAlert]) : forcer
    // l'ouverture ici la court-circuiterait sans que la politique de retour
    // le sache. C'est précisément ce qui arrivait au départ d'un col qui
    // commence sur un virage — les deux mécanismes se disputaient l'écran au
    // même tic, et la page battait ensuite entre la carte et la page de col à
    // chaque virage suivant. La page reste dans le défilement ; elle
    // s'ouvrira d'elle-même au prochain retour sur la carte si sa condition
    // tient toujours, juste pas poussée d'office pendant l'alerte.
    if (autoOpen != null && _lastAlert == RideAlert.none) {
      // Anime, et ferme au passage la page du menu qu'on vient déjà de fermer
      // — sans effet ici, mais c'est le seul chemin qui sait aussi recalculer
      // l'index brut le plus proche.
      _goToPage(_ridePages.indexOf(autoOpen), auto: true);
      return;
    }

    _reanchorOn(currentSpec);
  }

  /// Retrouve [currentSpec] dans le défilement qui vient de changer de forme
  /// (condition qui bascule, page masquée ou remise à la main) et corrige
  /// l'index brut en conséquence — sans la moindre animation, puisque rien ne
  /// doit bouger à l'écran pour une page qui n'a pas bougé. Si la page
  /// regardée vient au contraire de disparaître du défilement, retour à la
  /// carte, comme tout autre retour automatique.
  void _reanchorOn(RidePageSpec? currentSpec) {
    final keepIndex = currentSpec == null ? -1 : _ridePages.indexOf(currentSpec);
    if (keepIndex != -1) {
      final raw = rawPageFor(keepIndex, from: _rawPage, count: _pageCount);
      if (raw != _rawPage && _pages.hasClients) {
        // Marquée `auto` comme `_animateTo` : c'est une correction d'index
        // brut, pas un geste du cycliste — sans ce compteur, `_onPageChanged`
        // lirait `_userMoved = true` alors que rien n'a bougé à l'écran.
        _autoMoves++;
        _pages.jumpToPage(raw);
        _autoMoves--;
      }
      return;
    }

    _goToPage(_mapPage ?? 0, auto: true);
  }

  /// « Masquer cette page », depuis le menu ⋮ de [page] elle-même — voir
  /// `DashboardPage.onHidePage`. Range [page] derrière le menu pour la durée
  /// de la sortie, exactement comme si le site l'y avait mise, mais sans
  /// toucher au profil ni à rien qui survive au prochain lancement.
  ///
  /// [page] peut venir de trois origines — une page toujours-défilante qu'on
  /// range, une page conditionnelle **active** qu'on range malgré sa condition
  /// (voir [_manuallyHiddenConditional]), ou une page du menu rejointe à la
  /// main qu'on relâche — d'où le test sur [_conditionalPages]/
  /// [_activeConditional] puis [_baseMenuPages] : c'est l'origine qui dit quel
  /// ensemble corriger, [_ridePages] ne connaît que le résultat des trois.
  ///
  /// Refusé quand [page] est la dernière page hors carte du défilement — même
  /// garde que `RidePreset._promotedPage` côté profil : une sortie ne doit
  /// jamais se retrouver sans aucune page à faire défiler.
  void _hidePage(RidePageSpec page) {
    if (!_canHide(page)) return;

    _setMenuPage(null);
    final currentSpec = _pageCount > 0 ? _ridePages[_page] : null;

    setState(() {
      if (_conditionalPages.contains(page) && _activeConditional.contains(page)) {
        _manuallyHiddenConditional = {..._manuallyHiddenConditional, page};
      } else if (_baseMenuPages.contains(page)) {
        _manuallyShown = {..._manuallyShown}..remove(page);
      } else {
        _manuallyHidden = {..._manuallyHidden, page};
      }
    });
    // La carte a pu décaler : voir la note sur [_autoReturn].
    _autoReturn = AutoReturnPolicy(
      mapPage: _mapPage,
      holdAfterClear: _autoReturn.holdAfterClear,
    );

    _reanchorOn(currentSpec);
  }

  /// L'inverse de [_hidePage], depuis le menu ⋮ de la page ouverte — voir
  /// `DashboardPage.onShowPage`. Rejoint aussitôt le défilement sur [page],
  /// plutôt que de la laisser réapparaître dans un coin qu'on ne regarde pas :
  /// c'est justement pour la regarder qu'on vient de l'aller chercher. Même
  /// origine à trois ensembles que [_hidePage] : une page conditionnelle
  /// masquée à la main ressort de [_manuallyHiddenConditional] (sa condition
  /// tient toujours, elle reprend donc sa place tout de suite), une page
  /// rangée par le site rejoint [_manuallyShown], une page masquée à la main
  /// ressort de [_manuallyHidden].
  void _showPage(RidePageSpec page) {
    _setMenuPage(null);
    setState(() {
      if (_manuallyHiddenConditional.contains(page)) {
        _manuallyHiddenConditional = {..._manuallyHiddenConditional}..remove(page);
      } else if (_baseMenuPages.contains(page)) {
        _manuallyShown = {..._manuallyShown, page};
      } else {
        _manuallyHidden = {..._manuallyHidden}..remove(page);
      }
    });
    // La carte a pu décaler : voir la note sur [_autoReturn].
    _autoReturn = AutoReturnPolicy(
      mapPage: _mapPage,
      holdAfterClear: _autoReturn.holdAfterClear,
    );

    _goToPage(_ridePages.indexOf(page), auto: true);
  }

  /// [page] peut-elle rejoindre le menu sans vider le défilement de toute page
  /// hors carte ? Recalculée à chaque appel plutôt que mise en cache : c'est
  /// la seule façon de suivre ce que [_manuallyHidden] contient déjà.
  bool _canHide(RidePageSpec page) {
    final remaining = _ridePages.where((p) => !identical(p, page));
    return remaining.any((p) => p is! MapPageSpec);
  }

  bool _conditionMet(RidePageSpec page) => switch (page.menuCondition!) {
        PageMenuCondition.routeActive => _nav.value?.onRoute == true,
        PageMenuCondition.descending => _updateDescending(),
        PageMenuCondition.nearCol => _nearCol(),
        PageMenuCondition.workoutActive => widget.recorder.activeWorkout != null,
        PageMenuCondition.lapNamed => page.menuConditionLapName != null &&
            widget.recorder.lapStarted.value?.label == page.menuConditionLapName,
      };

  /// Entrée sous −3 %, sortie au-dessus de −1 % : la bande morte évite un
  /// battement de page à chaque tic quand la pente instantanée traîne près
  /// d'un seuil unique.
  bool _updateDescending() {
    final grade = widget.recorder.stats.gradePercent;
    if (grade == null) return _descending;
    if (!_descending && grade <= -3) _descending = true;
    if (_descending && grade > -1) _descending = false;
    return _descending;
  }

  /// Sur un col ([NavState.climb]), ou à moins de [_nearColLeadM] du départ du
  /// prochain — réutilise [traveledDistM]/[climbStatusOf], déjà écrits pour la
  /// liste des cols du tracé plutôt que de refaire ce calcul ici.
  static const _nearColLeadM = 500.0;

  bool _nearCol() => _climbEdge.climbing || _upcomingClimb.value != null;

  /// Le prochain col, à moins de [_nearColLeadM] du départ — `null` sinon, ou
  /// hors trace (voir [_findUpcomingClimb]). Recalculé à chaque tic
  /// (`_updateUpcomingClimb`, juste avant [_updateConditionalPages], qui en
  /// dépend via [_nearCol]) plutôt qu'à chaque trame : ni la position ni la
  /// liste des cols ne changent plus vite que la seconde qui les sépare.
  ///
  /// Sert à préremplir la carte de col sur la page Tours pendant l'approche
  /// (`LapClimbProfileCard`, `MetricSources.upcomingClimb`) : sans lui, cette
  /// carte n'a rien à montrer tant que le tour du col n'est pas ouvert, alors
  /// que la page, elle, s'ouvre déjà 500 m avant.
  final _upcomingClimb = ValueNotifier<RouteClimb?>(null);

  void _updateUpcomingClimb() => _upcomingClimb.value = _findUpcomingClimb();

  RouteClimb? _findUpcomingClimb() {
    final nav = _nav.value;
    // Hors trace, la position à laquelle la page accroche le tracé (et donc le
    // col qu'elle désigne) n'a plus rien de fiable — un GPS instable avant de
    // rejoindre l'itinéraire peut y faire retomber n'importe où, y compris en
    // plein milieu d'un col qu'on n'aborde pas.
    if (nav == null || nav.offRoute) return null;

    final climbs = _routeClimbs.value;
    final traveled = climbs == null ? null : traveledDistM(climbs, nav);
    if (climbs == null || traveled == null) return null;

    for (final climb in climbs.climbs) {
      if (climbStatusOf(climb, traveled) != ClimbStatus.upcoming) continue;
      if (climb.startDistM - traveled <= _nearColLeadM) return climb;
    }
    return null;
  }

  /// Va chercher les virages du tracé auprès du site, pour le filet natif.
  ///
  /// Sans jeton (reprise, navigation libre), la page est seule à savoir quel
  /// tracé elle suit : rien à récupérer, [_nativeTurns] reste nul.
  Future<void> _loadNativeTurnAlerts(NavigationTarget target) async {
    final token = target.shareToken;
    if (token == null) return;

    final hints = await fetchRouteVoiceHints(token, baseUrl: widget.baseUrl);
    if (!mounted || hints == null || hints.isEmpty) return;
    // Le tracé a pu changer pendant la requête : ne pas écraser la réponse
    // d'un jeton plus récent avec celle d'un jeton périmé.
    if (widget.target.shareToken != token) return;
    _nativeTurns = NativeTurnAlerts(hints);
  }

  /// Vibre et sonne pour un virage que la page ne peut plus annoncer
  /// elle-même.
  ///
  /// Même garde que [TurnProximity] : tant que le pont est frais, c'est la
  /// page qui alerte (bandeau, son, vibration) — vibrer et sonner en plus
  /// ferait double emploi à chaque virage d'une sortie parfaitement normale.
  void _checkNativeTurnAlert() {
    final turns = _nativeTurns;
    if (turns == null || turns.isDone) return;
    final state = _nav.value;
    if (state != null && !state.isStale(DateTime.now())) return;

    if (turns.update(widget.recorder.lastFix)) {
      unawaited(nativeTurnAlertBuzz());
      _nativeTurnSound.play();
    }
  }

  Future<void> _checkSession() async {
    final web = _web;
    if (web == null) return;
    await widget.session.record(await web.probeSession());
  }

  /// Changer de tracé sans quitter la sortie.
  ///
  /// La même feuille qu'au départ : elle sait déjà lire le catalogue en cache,
  /// coller un lien, et proposer la reprise. Le sélecteur ne fait que rendre une
  /// cible ; l'ouvrir appartient à la coquille, qui possède le WebView.
  Future<void> _chooseRoute() async {
    final target = await showModalBottomSheet<NavigationTarget>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NavigationPickerSheet(catalog: widget.routes),
    );

    if (target == null || !mounted) return;
    _openTarget(target);
  }

  /// Retirer le tracé : la carte reste, la navigation repart sans itinéraire.
  ///
  /// Avec confirmation, contrairement au choix d'un autre tracé — celui-là passe
  /// déjà par une feuille qu'on ne traverse pas par mégarde. Retirer, en
  /// revanche, est sans retour : `fresh=1` efface la session de la page, donc la
  /// progression avec elle.
  Future<void> _clearRoute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer l\'itinéraire ?'),
        content: const Text(
          'La carte et la position restent. La progression sur le tracé, elle, '
          'est perdue : le reprendre repartira du début.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    _openTarget(const NavigationTarget.free());
  }

  /// Démarrer (ou remplacer) un programme d'entraînement sans quitter la
  /// sortie — le cas soulevé en conception : décider en pleine route, se
  /// sentant en forme, de lancer un entraînement sans redémarrer la
  /// navigation. Même feuille que le FAB « Entraînement » de l'accueil
  /// (`WorkoutPickerSheet`) et le même magasin en cache — pas de
  /// re-téléchargement pour la même liste.
  ///
  /// `recorder.startWorkout` compte les jalons depuis CET instant, pas
  /// depuis le départ de la sortie (voir `RideRecorder.workoutElapsed`) :
  /// aucune distinction de code entre « choisi avant de partir » et « choisi
  /// en route ».
  Future<void> _chooseWorkout() async {
    final program = await showModalBottomSheet<TrainingProgram>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WorkoutPickerSheet(catalog: widget.trainingPrograms),
    );

    if (program == null || !mounted) return;
    widget.recorder.startWorkout(program);
  }

  /// Détacher le programme actif, sans arrêter la sortie ni l'enregistrement
  /// — les tours déjà ouverts restent lisibles sur une page Tours.
  void _stopWorkout() => widget.recorder.stopWorkout();

  /// Calibrer le capteur de puissance sans quitter la sortie.
  ///
  /// C'est en roulant qu'on voit une puissance dériver — au départ elle a l'air
  /// juste. Sortir de la navigation pour aller chercher l'écran des capteurs
  /// coûterait la carte et son démarrage, donc on ne le ferait pas : on finirait
  /// la sortie avec des watts faux, et une sortie fausse dans l'historique.
  Future<void> _calibratePower() =>
      showPowerCalibration(context, hub: widget.hub);

  /// Ouvre la carte hors-ligne du tracé affiché, sans quitter la sortie —
  /// même raison que [_calibratePower] : c'est en montagne, sans réseau, qu'on
  /// s'aperçoit qu'on aurait dû y penser avant de partir, mais c'est encore
  /// utile en cours de route pour la suite. Le téléchargement lui-même reste
  /// entièrement côté site ; voir `offline_download_dialog.dart`.
  Future<void> _downloadOffline() {
    final web = _web;
    if (web == null) return Future.value();
    return showOfflineDownloadDialog(
      context,
      state: _offline,
      start: () => unawaited(web.requestOfflineDownload()),
      cancel: () => unawaited(web.cancelOfflineDownload()),
      remove: () => unawaited(web.removeOfflineDownload()),
    );
  }

  /// Lance le téléchargement hors-ligne sans passer par le menu, quand le lien
  /// qui a ouvert cette sortie le demandait (`?download=1` sur le site, voir
  /// [NavigationTarget.autoDownloadOffline]) — la même boîte que
  /// [_downloadOffline], ouverte automatiquement dès que le pont annonce un
  /// tracé archivable, avec le téléchargement démarré dedans plutôt que
  /// d'attendre un tap sur « Télécharger ».
  ///
  /// La boîte reste ouverte tant qu'on ne l'a pas fermée : contrairement à un
  /// message qui s'efface tout seul, on peut toujours voir où en est le
  /// téléchargement (progression, erreur, terminé) en y revenant.
  ///
  /// Appelé à chaque message `'offline'` : le verrou [_autoOfflineTriggered]
  /// garantit un seul déclenchement par sortie, et `ready && !stale` évite de
  /// relancer un téléchargement déjà à jour.
  void _maybeAutoDownloadOffline() {
    if (!widget.target.autoDownloadOffline || _autoOfflineTriggered) return;
    final state = _offline.value;
    final web = _web;
    if (state == null || web == null) return;
    if (!state.supported || state.downloading) return;
    if (state.ready && !state.stale) return;

    _autoOfflineTriggered = true;
    unawaited(showOfflineDownloadDialog(
      context,
      state: _offline,
      start: () => unawaited(web.requestOfflineDownload()),
      cancel: () => unawaited(web.cancelOfflineDownload()),
      remove: () => unawaited(web.removeOfflineDownload()),
    ));
    unawaited(web.requestOfflineDownload());
  }

  /// Le bouton retour du téléphone, en **trois crans au plus** et dans l'ordre
  /// où le cycliste s'est éloigné de la carte : la page de données, puis la page
  /// web si elle s'est égarée ailleurs que sur le tracé ouvert, et enfin la
  /// sortie elle-même.
  ///
  /// **Les crans qui n'existent pas sont sautés.** Sans carte dans le profil, il
  /// n'y en a que deux : revenir à la première page, puis quitter. Le cran du
  /// milieu était sans fond avant `goBackInPage` : il dépilait l'historique du
  /// WebView entier, si bien qu'il fallait parfois appuyer cinq fois pour
  /// rentrer — et que les premiers appuis rouvraient au passage les tracés de la
  /// sortie.
  Future<void> _handleBack() async {
    // Une page ouverte depuis le menu se referme d'abord : elle recouvre tout le
    // reste, et c'est de là qu'on s'est le plus éloigné.
    if (_menuPage != null) {
      _setMenuPage(null);
      return;
    }

    final home = _mapPage ?? 0;
    if (_page != home) {
      _goToPage(home);
      return;
    }
    if (await (_web?.goBackInPage() ?? Future.value(false))) return;
    if (mounted) _leaveRide();
  }

  /// Quitter la sortie et retrouver l'accueil, **d'un seul geste**.
  ///
  /// Sans confirmation : rentrer est une chose qu'on fait souvent — jeter un œil
  /// à l'enregistrement, à un capteur — et une boîte à traverser à chaque fois
  /// rendrait le trajet aller-retour plus coûteux que ce qu'on va y chercher. Ce
  /// qui rend l'absence de garde-fou tenable, c'est la reprise : la sortie qu'on
  /// quitte est rendue à l'accueil, qui la repropose en tête et en un tap.
  ///
  /// L'enregistrement, lui, n'est jamais concerné : il vit au-dessus de la
  /// navigation et continue d'écrire pendant qu'on est à l'accueil.
  void _leaveRide() {
    final web = _web;
    // Sans carte, il n'y a rien à reprendre : la sortie n'avait pas de page web,
    // et proposer « Reprendre la navigation » à l'accueil ouvrirait une carte que
    // ce profil ne veut justement pas.
    Navigator.of(context).pop(
      web == null ? null : NavigationTarget.resume(label: web.target.label),
    );
  }

  /// Charge un autre tracé dans la page déjà montée.
  ///
  /// L'état de navigation est remis à zéro tout de suite : celui du tracé qu'on
  /// quitte ne dit plus rien de celui qui arrive, et le laisser en place ferait
  /// afficher un virage périmé pendant les secondes du chargement.
  void _openTarget(NavigationTarget target) {
    final web = _web;
    if (web == null) return;

    _nav.reset();
    // Le col qu'on gravissait, s'il y en avait un, appartient au tracé qu'on
    // quitte — sans ce reset, le maintien de ClimbEdgePolicy garderait la
    // page col ouverte jusqu'à 5 s sur le tracé qui vient de charger.
    _climbEdge.reset();
    _stableClimb.value = null;
    _upcomingClimb.value = null;
    _offline.reset();
    _nativeTurns = null;
    unawaited(_loadNativeTurnAlerts(target));
    web.openTarget(target);
    // Sur la carte : c'est là que le chargement se voit, et c'est ce qu'on veut
    // regarder juste après avoir choisi où aller.
    if (_mapPage case final page?) _goToPage(page);
  }

  /// Republie les zones obstruées de l'écran vers la page.
  ///
  /// `viewPadding` et non `padding` : la première garde la hauteur de
  /// l'obstruction physique même quand les barres système sont masquées. Le bas,
  /// lui, est retiré par [webInsetsFor] — le bandeau natif occupe cette zone.
  ///
  /// Le haut n'est **pas** le `viewPadding.top` brut : c'est
  /// [NotchBand.heightFor], qui inclut son plancher pour les écrans sans
  /// encoche. Pousser le `viewPadding.top` seul ferait croire à la page une
  /// zone obstruée plus courte que la bande réellement dessinée sur ces
  /// écrans, et sa bannière de virage se dessinerait sous la bande plutôt que
  /// juste en dessous.
  Future<void> _publishInsets() async {
    if (!mounted) return;
    await _web?.pushInsets(
      webInsetsFor(MediaQuery.viewPaddingOf(context))
          .copyWith(top: NotchBand.heightFor(context)),
    );
  }

  @override
  void didChangeMetrics() {
    // Rotation, écran partagé : les zones obstruées changent de place, et avec
    // elles la hauteur du bandeau, donc le cadre de la carte.
    _publishInsets();
  }

  /// Ouvre ou referme une page rangée derrière le menu.
  ///
  /// Le seul endroit qui touche à [_menuPage], parce que ce n'est jamais le seul
  /// effet : la carte passe sous une page opaque ou en ressort, et l'occlusion
  /// de la page web comme le rétroéclairage se lisent tous deux de [_onMap].
  /// Les répartir sur les appelants — le menu, le bouton fermer, le bouton
  /// retour, l'alerte — reviendrait à en oublier un.
  void _setMenuPage(int? index) {
    if (_menuPage == index) return;

    setState(() => _menuPage = index);
    _web?.setOccluded(!_onMap);
    _applyScreen(_screenPolicy.movedTo(onMap: _onMap));
  }

  /// Emmène le cycliste sur une page nommée : bouton retour, chargement d'un
  /// tracé, retour automatique. Par le chemin le plus court dans la boucle,
  /// jamais par le tour complet.
  ///
  /// Referme au passage la page du menu : elle est opaque et par-dessus tout le
  /// défilement, donc y « aller » sans la retirer ne changerait rien à l'écran —
  /// c'est le cas du bouton retour pressé depuis un bilan.
  void _goToPage(int page, {bool auto = false}) {
    _setMenuPage(null);
    _animateTo(
      rawPageFor(page, from: _rawPage, count: _pageCount),
      auto: auto,
    );
  }

  /// Avance ou recule d'une page, sans se soucier de laquelle : c'est ce que
  /// demandent les bandes du bord, qui parlent en gestes et pas en destinations.
  ///
  /// Une page du menu ouverte absorbe le premier geste pour se refermer,
  /// plutôt que de laisser le défilement changer sous elle : les bandes de
  /// bord n'existent que sur la carte (donc menu forcément fermé), seul le
  /// bouton Di2 peut appeler ceci pendant qu'une page du menu est affichée.
  void _stepPage(int direction) {
    if (_menuPage != null) {
      _setMenuPage(null);
      return;
    }
    _animateTo(_rawPage + direction);
  }

  /// [auto] : le déplacement vient de la politique, pas du cycliste. C'est ce
  /// qui empêche le retour automatique de se prendre lui-même pour une reprise
  /// en main et de s'annuler à peine déclenché.
  void _animateTo(int rawPage, {bool auto = false}) {
    if (!_pages.hasClients) return;
    if (auto) _autoMoves++;
    _pages
        .animateToPage(
          rawPage,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (auto) _autoMoves--;
    });
  }

  void _onPageChanged(int rawPage) {
    // Tout ce qui n'a pas été décidé ici l'a été par un doigt : un glissé sur
    // une page de données ne passe par aucun de nos appels, il ne se voit que là.
    if (_autoMoves == 0) _userMoved = true;
    setState(() => _rawPage = rawPage);
    // La page web n'est plus regardée : qu'elle cesse d'animer. Elle continue en
    // revanche de suivre la position et de publier son état — c'est tout
    // l'intérêt de la garder montée.
    _web?.setOccluded(!_onMap);
    _applyScreen(_screenPolicy.movedTo(onMap: _onMap));
  }

  /// Bouton « Mettre en veille » d'une page de données ([SleepControl]) :
  /// ramène le cycliste sur la carte — seule à savoir s'endormir — puis le lui
  /// demande (`requestSleep`, même chemin que l'appui long côté site,
  /// `toggleScreenOffManual` dans `RouteNavigation.vue`). Sans ce retour, le
  /// voile se poserait hors champ et `ScreenPolicy` ne dimmerait rien,
  /// `_asleep` exigeant `_onMap`.
  void _sleep() {
    if (_mapPage case final page?) _goToPage(page);
    unawaited(_web?.requestSleep());
  }

  /// Répartit un geste résolu ([Di2ButtonGesturePolicy]) vers l'action que le
  /// profil de sortie assigne à ce canal et à ce geste — rien si le profil
  /// n'y a rien mis pour ce geste-là.
  void _dispatchButtonGesture(Di2ButtonChannel channel, Di2ButtonGesture gesture) {
    debugPrint('[boutons] canal $channel geste $gesture');
    // Toujours mis à jour, qu'une action soit assignée ou non : c'est un
    // repère de diagnostic (« quel geste vient d'être vu ? »), pas une
    // confirmation d'exécution.
    setState(() {
      _buttonFlash = ButtonGestureFlash(channel, gesture, _buttonFlashSeq++);
    });
    final actions = switch (channel) {
      Di2ButtonChannel.one => _preset.buttons.channel1,
      Di2ButtonChannel.two => _preset.buttons.channel2,
      Di2ButtonChannel.three => _preset.buttons.channel3,
      Di2ButtonChannel.four => _preset.buttons.channel4,
    };
    final action = switch (gesture) {
      Di2ButtonGesture.click => actions.click,
      Di2ButtonGesture.doubleClick => actions.doubleClick,
      Di2ButtonGesture.longPress => actions.longPress,
    };
    if (action != null) _performButtonAction(action);
  }

  void _performButtonAction(ButtonAction action) {
    switch (action) {
      case NextPageAction():
        _stepPage(1);
      case PreviousPageAction():
        _stepPage(-1);
      case RingBellAction(:final sound):
        unawaited(_buttonBell.toggle(sound));
      case StartLapAction(:final series):
        // Même garde que `MarkLapControl` (`mark_lap_block.dart`) : un tour
        // ne veut rien dire hors enregistrement.
        if (widget.recorder.isActive) widget.recorder.markLap(series);
      case EnterSleepAction():
        _sleep();
      case ExitSleepAction():
        unawaited(_web?.requestWake());
      case ToggleSleepAction():
        // `_screenPolicy.dimmed` et non un état à soi : c'est déjà ce qui
        // pilote le rétroéclairage (`_applyScreen`), donc ce que le cycliste
        // voit réellement. Pendant une alerte radar, l'écran est rallumé sans
        // que la page ait renoncé à sa veille (`dimmed` retombe à faux le
        // temps de l'alerte) — le bouton rejoue alors une entrée en veille
        // déjà demandée, sans effet côté site (`enter` s'y sait idempotent).
        if (_screenPolicy.dimmed) {
          unawaited(_web?.requestWake());
        } else {
          _sleep();
        }
      case GoToPageAction(:final pageKey):
        _goToPageByKey(pageKey);
      case TogglePauseAction():
        // Même garde que `StartLapAction` : hors enregistrement, rien à
        // suspendre ou reprendre.
        switch (widget.recorder.state) {
          case RecorderState.recording:
            widget.recorder.pause();
          case RecorderState.paused:
            widget.recorder.resume();
          case RecorderState.idle:
            break;
        }
    }
  }

  /// Résout un [GoToPageAction] par la clé stable des pages
  /// ([RidePageSpec.key]) plutôt que par un index qui se décale au moindre
  /// réordonnancement du profil. Cherche d'abord dans le défilement, puis
  /// dans le menu ; sans effet si aucune page ne porte cette clé — profil
  /// réédité entre-temps, ou site plus ancien que ce réglage — jamais une
  /// erreur.
  void _goToPageByKey(String pageKey) {
    final ridePages = _ridePages;
    for (var i = 0; i < ridePages.length; i++) {
      if (ridePages[i].key == pageKey) {
        _goToPage(i);
        return;
      }
    }
    final menuPages = _menuPages;
    for (var i = 0; i < menuPages.length; i++) {
      if (menuPages[i].key == pageKey) {
        _setMenuPage(i);
        return;
      }
    }
  }

  /// Messages venus de la page.
  ///
  /// `ready` : la page annonce que son pont est en place.
  /// `screen` : elle entre ou sort de sa veille, et demande le rétroéclairage
  /// correspondant — ce qu'un navigateur ne sait pas faire lui-même.
  /// `nav` : où en est la navigation (virage, hors-trace, arrivée, col).
  /// `climb_profile` : le profil gradué du col en cours, poussé une seule
  /// fois par col (voir climb_profile.dart) — le `nav.climb` scalaire, lui,
  /// arrive chaque seconde.
  /// `route_climbs` : la liste ordonnée des cols du tracé entier, poussée une
  /// fois par tracé (voir route_climbs.dart) — pas par col, contrairement à
  /// `climb_profile`.
  /// `route_profile` : le profil d'altitude du tracé entier, poussé une fois
  /// par tracé (voir route_profile.dart) — même cadence que `route_climbs`.
  /// `rider_profile` : les seuils du cycliste, relayés depuis le site.
  /// `training_budget` : ce qu'il reste à faire aujourd'hui, et le plafond que la
  /// fatigue autorise — calculés par le site, qui seul a l'historique.
  /// `offline` : où en est la carte hors-ligne du tracé affiché (voir
  /// `OfflineMapNotifier` et `companionBridge.ts` côté Rails).
  void _onPageMessage(Map<dynamic, dynamic> message) {
    switch (message['type']) {
      case 'ready':
        _web?.bridge.notifyPageReloaded();
      case 'nav':
        _nav.accept(message);
        final climb = _nav.value?.climb;
        // Front stabilisé (voir ClimbEdgePolicy) : `climb` brut peut
        // flickerer `null`/non-`null` d'une trame à l'autre près de la
        // frontière du col, en simulation surtout. `edge` ne vaut vrai qu'à
        // l'entrée et à la sortie *confirmées* — jamais à un flicker.
        final edge = _climbEdge.update(now: DateTime.now(), climbing: climb != null);
        final hasClimb = _climbEdge.climbing;
        // Même maintien que _climbProfile, pour la même raison : pendant un
        // flicker vers `null`, la pastille et la page col doivent continuer à
        // montrer le dernier col connu plutôt que de clignoter avec le brut.
        if (climb != null) {
          _stableClimb.value = climb;
        } else if (!hasClimb) {
          _stableClimb.value = null;
        }
        if (edge) {
          // Isole la montée dans son propre tour de la série `cols` — sans
          // effet si aucune page ou bouton du profil ne la déclare
          // (`RideRecorder.markLap`, no-op sur une série inconnue).
          widget.recorder.markLap(climbLapSeries);
          // `edge` porte déjà le front stabilisé : `hasClimb` vrai veut dire
          // qu'on vient d'entrer, faux qu'on vient de sortir. Rien à relire
          // sur `climb`, qui peut flickerer juste autour de cette frontière.
          if (_preset.climb.sounds) {
            _climbSound.play(hasClimb ? ClimbCue.start : ClimbCue.end);
          }
          // Chaque nouveau col repart de l'affichage choisi sur le site — le
          // tap reste libre de changer d'avis pour ce col-ci, voir
          // `_climbExpanded` plus haut.
          if (hasClimb) _climbExpanded.value = _preset.climb.expandedByDefault;
        }
        if (!hasClimb) {
          if (edge) {
            _climbProfile.reset();
            _climbExpanded.value = false;
          }
        } else if (climb == null) {
          // Flicker vers `null` (raw) pendant le maintien de
          // [ClimbEdgePolicy] : rien à refaire, le profil déjà affiché reste
          // tel quel — c'est précisément ce qui évite la page vide.
        } else if (_findRouteClimb(climb.id)?.profile case final profile?) {
          // Le profil de CE col est déjà dans `route_climbs`, reçu une fois
          // pour tout le tracé au chargement (voir RouteClimb.profile) —
          // résolu à chaque trame tant que le col dure, pas seulement au
          // front montant : une liste reçue en retard (démarrage de sortie)
          // se rattrape ainsi toute seule, sans attendre un nouveau front.
          // Un site plus ancien que ce champ (ou une liste pas encore reçue)
          // laisse `_climbProfile` tel quel : c'est alors le message
          // `climb_profile` classique, ci-dessous, qui le remplira.
          _climbProfile.value = profile;
          // Pas de garde sur `edge` : au front montant, `route_climbs` n'est
          // presque jamais encore là (message séparé, pas forcément reçu la
          // même trame) — le tour resterait étiqueté `null` pour toujours.
          // `tagClimb` vise toujours le dernier tour ouvert, donc l'appeler
          // une trame plus tard, une fois le profil connu, tague encore le
          // bon tour ; rien à défaire si c'est déjà fait (même id réécrit).
          widget.recorder.tagClimb(climbLapSeries, profile.id);
        }
      case 'climb_profile':
        // Repli pour un site plus ancien que `route_climbs.climbs[].points`,
        // qui ne pousse alors le profil qu'une fois par col, à l'entrée (voir
        // la doc de ClimbProfile) — la résolution normale, ci-dessus,
        // l'emporte déjà dans l'immense majorité des cas.
        _climbProfile.accept(message);
        // Le tour que le front montant a ouvert sur la série `cols` est
        // forcément celui de ce col-ci — voir `RideRecorder.tagClimb`. C'est
        // ce qui permet à la page Tours de nommer le tour comme le composant
        // Cols du tracé plutôt que « Tour N ». Sans effet si le tour a déjà
        // été étiqueté ci-dessus (`tagClimb` réécrit le même id sur le même
        // dernier tour).
        //
        // **Gardé par `_climbEdge.climbing`** : ce message et la trame `nav`
        // qui ouvre le tour (front montant, ci-dessus) sont deux canaux
        // séparés, et rien ne garantit que celui-ci arrive après. Reçu avant
        // — observé en pratique, `climb_profile` grillant la trame `nav`
        // suivante —, `tagClimb` retomberait sur le tour *encore ouvert
        // avant le col* (le plat qui précède) et l'étiquetterait à tort :
        // ce tour-là afficherait alors le profil du col qu'il ne couvre pas.
        if (_climbProfile.value case final profile? when _climbEdge.climbing) {
          widget.recorder.tagClimb(climbLapSeries, profile.id);
        }
      case 'route_climbs':
        _routeClimbs.accept(message);
      case 'route_profile':
        _routeProfile.accept(message);
      case 'offline':
        _offline.accept(message);
        _maybeAutoDownloadOffline();
      case 'rider_profile':
        widget.riderProfile.record(RiderProfile.fromJson(message['profile']));
      case 'training_budget':
        widget.trainingBudget.record(
          TrainingBudget.fromJson(message['budget']),
        );
      case 'screen':
        _applyScreen(
          _screenPolicy.pageRequested(message['state'] == 'dimmed'),
        );
    }
  }

  /// N'appelle le réglage de luminosité que sur les transitions : la page peut
  /// redemander sa veille à chaque rechargement, et changer la luminosité
  /// globale du téléphone n'est pas une opération à répéter pour rien.
  ///
  /// Le **rendu**, lui, est refait à chaque fois, et c'est le point : la page
  /// radar tient à `radarWake`, pas à `dimmed`, et les deux ne changent pas
  /// ensemble. Le cycliste qui tape pour réveiller la navigation pendant une
  /// alerte ne touche pas à la luminosité — le radar tenait déjà l'écran
  /// allumé — et se retrouvait donc devant les mètres en noir jusqu'à ce que la
  /// voiture passe, sans moyen de revenir à la carte.
  void _applyScreen(bool changed) {
    if (changed) {
      if (_screenPolicy.dimmed) {
        _screen.dim(_preset.screen.dimLevel);
      } else {
        _screen.restore();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _buttonTick?.cancel();
    _compassTick?.cancel();
    unawaited(_remoteButtonSub?.cancel());
    _buttonBell.dispose();
    // Le magnétomètre s'éteint avec la sortie : c'est le seul capteur de ce
    // dossier qui coûterait de la batterie une fois l'écran refermé.
    unawaited(widget.compass?.stop());
    _nav.removeListener(_decideReturn);
    widget.recorder.lapStarted.removeListener(_onLapStarted);
    _lapToastTimer?.cancel();
    _lapToast.dispose();
    _radar.removeListener(_onRadar);
    _radar.dispose();
    _mutedRadar.dispose();
    _radarSound.dispose();
    _climbSound.dispose();
    unawaited(_workoutCue.dispose());
    _workoutChangeTimer?.cancel();
    _workoutChangeAlert.dispose();
    _battery.removeListener(_onBatteryStatus);
    _battery.dispose();
    _batterySound.dispose();
    _batteryAlert.dispose();
    _reminderBell.dispose();
    _reminderAlert.dispose();
    unawaited(_nativeTurnSound.dispose());
    // Filet de sécurité : quitter la navigation en veille (bouton retour, page
    // qui plante) ne doit pas laisser l'appareil à 1 % de luminosité.
    _screen.restore();
    // Les barres reviennent en quittant la navigation : l'accueil est un écran
    // d'appli ordinaire, avec son horloge et ses gestes.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _web?.dispose();
    _nav.dispose();
    _climbProfile.dispose();
    _stableClimb.dispose();
    _upcomingClimb.dispose();
    _routeClimbs.dispose();
    _routeProfile.dispose();
    _climbExpanded.dispose();
    _offline.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bandHeight = RideBottomBand.heightFor(context);
    final webView = _webView;
    // Calculée ici et pas dans la liste des enfants du `Stack` : `Positioned`
    // doit rester l'enfant direct du `Stack` pour valoir quelque chose, une
    // `Builder` intercalée pour ne serait-ce que nommer cette page le
    // dépositionnerait entièrement.
    final menuPageIndex = _menuPage;
    final openedMenuPage = menuPageIndex == null ? null : _menuPages[menuPageIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Pas de SafeArea autour de la carte : en immersif il n'y a plus de
        // barres à contourner, et l'encoche éventuelle est mieux occupée par la
        // carte que par une bande noire.
        // **Chaque enfant porte une clé**, et ce n'est pas une précaution de
        // style. Plusieurs d'entre eux vont et viennent (la zone de glissé, la
        // page du menu, la page radar) : sans clé, une apparition décale tous
        // les suivants d'un cran et Flutter réapparie les éléments par leur
        // rang — le `PageView` héritait alors de l'élément du voisin, perdait sa
        // position de défilement et repartait n'importe où. C'est exactement ce
        // qu'on voyait : un glissé sur deux qui revenait à la carte, et le
        // numéro de page qui ne paraissait plus.
        body: Stack(
          children: [
            // La carte, tout au fond et pour toute la sortie — quand il y en a
            // une.
            if (webView != null)
              Positioned(
                key: const ValueKey('web'),
                left: 0,
                right: 0,
                top: 0,
                bottom: bandHeight,
                child: webView,
              ),
            // Le glissé d'un doigt sur la carte, qui mène le défilement. Entre
            // la page web et les pages de données : il ne prend que le glissé
            // horizontal d'un seul doigt et laisse passer l'appui, le vertical
            // et le second doigt — c'est-à-dire ce dont la carte a besoin depuis
            // qu'elle se déplace à deux doigts.
            if (webView != null)
              Positioned(
                key: const ValueKey('glisse-carte'),
                left: 0,
                right: 0,
                top: 0,
                bottom: bandHeight,
                child: MapSwipeZone(pages: _pages, enabled: _onMap),
              ),
            // Les pages de données, dans le même cadre, opaques quand elles sont
            // là. La page carte est vide : c'est le WebView qu'on voit à travers.
            //
            // Construite à la demande et sans fin, parce que le catalogue tourne
            // en boucle : l'index brut du défilement ne revient jamais en
            // arrière, c'est [pageOf] qui le replie sur les pages réelles.
            //
            // Hors du test de touche sur la carte, et pas d'une autre physique :
            // c'est [MapSwipeZone] qui lui pousse le glissé, ce qu'une physique
            // non défilante avalerait. Changer de physique en cours de route
            // était d'ailleurs le second piège — un `Scrollable` reconstruit
            // alors sa position et laisse tomber le geste en train de se faire.
            Positioned(
              key: const ValueKey('pages'),
              left: 0,
              right: 0,
              top: 0,
              bottom: bandHeight,
              child: IgnorePointer(
                ignoring: _onMap,
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, rawPage) =>
                      _pageAt(pageOf(rawPage, count: _pageCount)),
                ),
              ),
            ),
            // La page ouverte depuis le menu, par-dessus le défilement et la
            // carte.
            //
            // Dans la même pile et pas dans une route poussée : le bandeau, les
            // jauges du radar, le cadre d'alerte et la bande de l'encoche
            // appartiennent à la coquille, et une route par-dessus les
            // emporterait tous. On consulte un bilan **pendant une sortie** —
            // une voiture qui remonte doit se voir de là comme d'ailleurs.
            if (openedMenuPage case final openedPage?)
              Positioned(
                key: const ValueKey('menu'),
                left: 0,
                right: 0,
                top: 0,
                bottom: bandHeight,
                child: DashboardPage(
                  // Identité de la page, pas de sa position : `openedPage`
                  // change d'un tap à l'autre sans jamais démonter ce nœud
                  // (seul `Positioned` porte une clé fixe, 'menu') — sans
                  // cette clé-ci, Flutter réutilisait l'Element d'une page à
                  // l'autre et une page de tours héritait du `_selectedIndex`
                  // laissé par la précédente.
                  key: ObjectKey(openedPage),
                  page: openedPage,
                  sources: _sources,
                  radar: _preset.sensors.radar ? _radar : null,
                  battery: _battery,
                  // Ni liste de pages ni menu d'actions : on referme pour
                  // retrouver ceux de la page d'où l'on vient — `onClose`
                  // l'emporte sur `_actionsMenu()` dans `DashboardPage._header`,
                  // quels que soient les callbacks ci-dessous.
                  //
                  // Ces callbacks-là, en revanche, ne nourrissent pas le menu
                  // d'actions mais les **blocs posés sur la page**
                  // (`route`/`change_route`/`clear_route`/`sleep`) : sans eux,
                  // une page rangée derrière le menu qui en porte un se
                  // retrouvait avec un bouton grisé, indistinguable d'une case
                  // vide, une fois rouverte depuis là. Même garde `hasMap` que
                  // `_pageAt`.
                  onChooseRoute: _preset.hasMap ? _chooseRoute : null,
                  onClearRoute: _preset.hasMap ? _clearRoute : null,
                  onSleep: _preset.hasMap ? _sleep : null,
                  offlineMap: _preset.hasMap ? _offline : null,
                  onDownloadOffline: _preset.hasMap ? _downloadOffline : null,
                  onCalibratePower:
                      powerCalibrationAvailable(widget.hub) ? _calibratePower : null,
                  // Sans rapport avec la carte, contrairement aux commandes
                  // ci-dessus : un programme d'entraînement se démarre aussi
                  // bien sur home-trainer.
                  onStartWorkout: _chooseWorkout,
                  onStopWorkout:
                      widget.recorder.activeWorkout != null ? _stopWorkout : null,
                  onClose: () => _setMenuPage(null),
                  // Toute page ouverte depuis le menu peut rejoindre le
                  // défilement — qu'elle y ait été rangée par le site ou
                  // masquée à la main (`_hidePage` en distingue l'origine) —
                  // et pourra en ressortir ensuite comme n'importe quelle
                  // autre page, depuis son propre menu ⋮ une fois affichée.
                  onShowPage: () => _showPage(openedPage),
                ),
              ),
            // La page radar : le seul écran qui s'invite. Elle ne paraît que
            // pendant la veille, là où la page web est sous son voile noir et n'a
            // rien à dire d'une voiture qu'elle ne voit pas.
            if (_screenPolicy.radarWake)
              Positioned(
                key: const ValueKey('reveil-radar'),
                left: 0,
                right: 0,
                top: 0,
                bottom: bandHeight,
                child: ValueListenableBuilder<RadarView>(
                  valueListenable: _radar,
                  builder: (context, radar, _) => RadarWakePage(view: radar),
                ),
              ),
            _gutter(RadarGaugeSide.left, bandHeight),
            _gutter(RadarGaugeSide.right, bandHeight),
            Positioned(
              key: const ValueKey('bandeau'),
              left: 0,
              right: 0,
              bottom: 0,
              child: RideBottomBand(
                bands: _preset.bands,
                sources: _sources,
                recorder: widget.recorder,
                radar: _preset.sensors.radar ? _radar : null,
                // Toujours branché, sans filtrer sur la découverte GATT : la
                // coquille ne se redessine pas quand le capteur finit sa
                // découverte, et un tap qui ne ferait rien serait pris pour un
                // écran gelé.
                onCalibratePower: _calibratePower,
                // Sans carte, il n'y a personne à endormir — même garde que
                // pour la commande de la grille (`DashboardPage.onSleep`
                // plus bas).
                onSleep: _preset.hasMap ? _sleep : null,
                // Sans rapport avec la carte, même raison que
                // `DashboardPage.onStartWorkout` plus bas : un programme se
                // démarre aussi bien sur home-trainer.
                onChooseWorkout: _chooseWorkout,
                // Toujours branché, comme dans le menu ⋮ (`DashboardPage.
                // onLeaveRide` plus bas) : rentrer a un sens avec ou sans
                // carte.
                onLeaveRide: _leaveRide,
                // Sans carte, il n'y a aucune page à qui adresser la demande
                // — même garde que `DashboardPage.onChooseRoute`/
                // `onClearRoute` plus bas.
                onChooseRoute: _preset.hasMap ? _chooseRoute : null,
                onClearRoute: _preset.hasMap ? _clearRoute : null,
              ),
            ),
            // Le numéro de la page, juste au-dessus du bandeau et le temps de le
            // lire. C'est ce qui remplace les pastilles qu'il portait.
            //
            // Au-dessus du bandeau et pas au milieu de l'écran : le regard y est
            // déjà — c'est de là que part le glissé des bandes du bord — et un
            // chiffre en plein centre recouvrirait la case de grille ou le
            // virage qu'on venait justement chercher.
            //
            // Après le bandeau dans la pile, donc par-dessus les pages et la
            // page du menu. Sous le cadre d'alerte en revanche : une voiture qui
            // remonte passe avant de savoir sur quelle page on est.
            Positioned(
              key: const ValueKey('numero-de-page'),
              left: 0,
              right: 0,
              bottom: bandHeight + 12,
              child: Center(
                child: RidePageFlash(page: _page, count: _pageCount),
              ),
            ),
            // Au-dessus du numéro de page plutôt qu'au même endroit : un clic
            // sur un canal assigné à la page suivante/précédente déclenche les
            // deux repères à la fois, et ils se chevaucheraient sinon.
            Positioned(
              key: const ValueKey('geste-bouton'),
              left: 0,
              right: 0,
              bottom: bandHeight + 12 + 46,
              child: Center(
                child: RideButtonFlash(event: _buttonFlash),
              ),
            ),
            // La bande de l'encoche : jusqu'à une mesure de chaque côté de la
            // caméra selfie, sur l'emplacement de l'ancienne
            // `RadarDistanceBadges`. Avant la pastille de col et le cadre
            // d'alerte dans la pile, pour que les deux continuent de se
            // dessiner par-dessus elle — le radar garde la priorité visuelle
            // sur ce que le profil y a placé.
            Positioned(
              key: const ValueKey('encoche'),
              left: 0,
              right: 0,
              top: 0,
              child: NotchBand(
                notch: _preset.notch,
                sources: _sources,
                recorder: widget.recorder,
                radar: _preset.sensors.radar ? _radar : null,
                onSleep: _preset.hasMap ? _sleep : null,
                onChooseWorkout: _chooseWorkout,
                onLeaveRide: _leaveRide,
                onChooseRoute: _preset.hasMap ? _chooseRoute : null,
                onClearRoute: _preset.hasMap ? _clearRoute : null,
              ),
            ),
            // La pastille du tronçon en cours d'un programme d'entraînement :
            // épinglée tout en haut à gauche, au ras du bord (même abscisse
            // que la boussole, qui ne paraît que sur la carte) — pas décalée
            // de la gouttière radar comme la pastille de col, qui reste à
            // droite. Sur une page de données, l'en-tête (icône + titre,
            // `DashboardPage._header`) commence à la même hauteur — mais lui
            // aussi à gauche, jamais au centre comme avant ce réglage, les
            // deux ne se recouvrent donc plus. Ni carte ni GPS requis,
            // contrairement à la boussole/pastille de col : un programme se
            // déroule aussi bien sur home-trainer.
            //
            // Dérivée à chaque tic de [widget.recorder] plutôt que d'un
            // curseur propre — même patron que `WorkoutSegmentCard` : c'est
            // une pastille, pas une politique de franchissement, elle n'a
            // rien à se souvenir entre deux rebuilds.
            if (_preset.workout.badge)
              Positioned(
                key: const ValueKey('entrainement-pastille'),
                top: 8,
                left: 8,
                child: SafeArea(
                  bottom: false,
                  child: ListenableBuilder(
                    listenable: widget.recorder,
                    builder: (context, _) {
                      final program = widget.recorder.activeWorkout;
                      final elapsed = widget.recorder.workoutElapsed;
                      final milestone = program != null && elapsed != null
                          ? program.milestoneAt(elapsed)
                          : null;
                      if (milestone == null) return const SizedBox.shrink();
                      final remaining = program!.remainingAt(elapsed!);
                      // L'aperçu du tronçon suivant, dans les dernières secondes
                      // de celui-ci seulement — pas plus tôt, sinon la pastille
                      // annoncerait un changement bien avant qu'il ne compte
                      // vraiment.
                      final next = remaining != null && remaining <= WorkoutBadge.upcomingLead
                          ? program.nextMilestoneAt(elapsed)
                          : null;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WorkoutBadge(milestone: milestone, remaining: remaining),
                          if (next != null) ...[
                            const SizedBox(height: 6),
                            WorkoutBadge(milestone: next, upcoming: true),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            // La pastille de col : repliée, épinglée en haut à droite. Posée
            // après le bandeau/numéro de page pour rester visible même
            // par-dessus la veille radar (reveil-radar) —
            // un col en cours ne doit pas disparaître derrière une alerte
            // voiture, les deux sont des informations indépendantes.
            Positioned(
              key: const ValueKey('col-pastille'),
              top: 8,
              right: RadarSideGauge.width + 8,
              child: ValueListenableBuilder<NavClimb?>(
                valueListenable: _stableClimb,
                builder: (context, stableClimb, _) {
                  // Le col simulé prime sur le vrai : c'est un banc d'essai,
                  // pas un second col qui s'ajouterait au premier.
                  final climb = _debugClimb ?? stableClimb;
                  if (climb == null) return const SizedBox.shrink();
                  return ValueListenableBuilder<bool>(
                    valueListenable: _climbExpanded,
                    builder: (context, expanded, _) => expanded
                        ? const SizedBox.shrink()
                        : SafeArea(
                            bottom: false,
                            child: ClimbBadge(
                              climb: climb,
                              onTap: () => _climbExpanded.value = true,
                            ),
                          ),
                  );
                },
              ),
            ),
            // La carte de col dépliée : ancrée en bas, au-dessus du bandeau —
            // même position que .nav-climb côté site (bottom-anchored), pour
            // que le geste de repli tape au même endroit qu'on vient de
            // taper pour déplier.
            Positioned(
              key: const ValueKey('col-profil'),
              left: 12,
              right: 12,
              bottom: bandHeight + 12,
              child: ValueListenableBuilder<bool>(
                valueListenable: _climbExpanded,
                builder: (context, expanded, _) {
                  if (!expanded) return const SizedBox.shrink();
                  return ValueListenableBuilder<NavClimb?>(
                    valueListenable: _stableClimb,
                    builder: (context, stableClimb, _) {
                      final debugClimb = _debugClimb;
                      final climb = debugClimb ?? stableClimb;
                      if (climb == null) return const SizedBox.shrink();
                      return ValueListenableBuilder<ClimbProfile?>(
                        valueListenable: _climbProfile,
                        builder: (context, profile, _) => ClimbProfileOverlay(
                          climb: climb,
                          profile: debugClimb != null ? _debugClimbProfile : profile,
                          onTap: () => _climbExpanded.value = false,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Pastille de boussole, en haut à gauche (la pastille de col
            // occupe déjà le coin droit) : cap mesuré, et bouton pour forcer
            // sa priorité sur la course GPS — utile sous un couvert
            // forestier (voir `RiderCompass.forced`).
            if (_onMap)
              Positioned(
                key: const ValueKey('boussole'),
                top: 8,
                left: 8,
                child: SafeArea(
                  bottom: false,
                  child: ValueListenableBuilder<(double, bool)?>(
                    valueListenable: _compassReading,
                    builder: (context, reading, _) {
                      if (reading == null) return const SizedBox.shrink();
                      final (heading, trusted) = reading;
                      return CompassBadge(
                        headingDeg: heading,
                        trusted: trusted,
                        forced: widget.compass?.forced ?? false,
                        onTap: _toggleCompassForced,
                      );
                    },
                  ),
                ),
              ),
            // La veille par appui long n'existe plus que sur la carte, où
            // c'est le site qui la détecte et s'endort lui-même — la coquille
            // n'a donc plus de couche d'appui ni de voile à poser ici.
            // Le cadre par-dessus tout, bandeau compris : l'alerte n'appartient
            // pas à la carte, elle appartient à la sortie.
            //
            // Sauf profil qui a coupé l'habillage : le radar ne se voit alors
            // que dans les composants posés exprès. Le capteur, lui, tourne
            // toujours — les tonalités et le réveil d'écran ne dépendent pas
            // d'ici.
            if (_overlay)
              Positioned.fill(
                key: const ValueKey('cadre-radar'),
                child: ValueListenableBuilder<RadarView>(
                  valueListenable: _radar,
                  builder: (context, radar, _) =>
                      RadarFrame(severity: radar.severity),
                ),
              ),
            // Le bandeau de batterie faible : au sommet de la pile, visible
            // quelle que soit la page (contrairement au réveil radar, qui n'a
            // de sens que sous le voile de la carte) et même par-dessus le
            // cadre d'alerte radar. Pure information, aucun geste à voler —
            // voir `BatteryAlertBanner`.
            Positioned(
              key: const ValueKey('alerte-batterie'),
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<List<BatteryStatus>>(
                valueListenable: _batteryAlert,
                builder: (context, devices, _) => devices.isEmpty
                    ? const SizedBox.shrink()
                    : BatteryAlertBanner(devices: devices),
              ),
            ),
            // Le rappel périodique : au sommet de tout, batterie comprise —
            // c'est la « grosse alerte » qu'on ne doit pas manquer, et elle
            // n'a rien d'urgent à céder à une batterie faible.
            Positioned(
              key: const ValueKey('alerte-rappel'),
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<List<ReminderSpec>>(
                valueListenable: _reminderAlert,
                builder: (context, reminders, _) => reminders.isEmpty
                    ? const SizedBox.shrink()
                    : ReminderBanner(reminders: reminders),
              ),
            ),
            // Le popup de changement de tronçon : au centre, au-dessus de
            // tout — c'est le front qu'on ne doit pas manquer, même par-dessus
            // une alerte batterie ou un rappel qui tomberait au même instant.
            Positioned.fill(
              key: const ValueKey('popup-entrainement'),
              child: ValueListenableBuilder<WorkoutMilestone?>(
                valueListenable: _workoutChangeAlert,
                builder: (context, milestone, _) => milestone == null
                    ? const SizedBox.shrink()
                    : WorkoutChangePopup(milestone: milestone),
              ),
            ),
            // Le toast d'ouverture de tour : en bas, au plus près du geste
            // (bandeau, encoche) qui vient de le déclencher — voir
            // _onLapStarted.
            Positioned.fill(
              key: const ValueKey('toast-tour'),
              child: ValueListenableBuilder<String?>(
                valueListenable: _lapToast,
                builder: (context, label, _) => label == null
                    ? const SizedBox.shrink()
                    : LapStartedToast(label: label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La page d'un index du défilement.
  ///
  /// La carte ne se dessine pas ici — elle est au fond de la pile, et cette
  /// entrée du `PageView` est donc transparente.
  Widget _pageAt(int index) {
    final page = _ridePages[index];
    if (page is MapPageSpec) return const SizedBox.shrink();

    return DashboardPage(
      // Identité de la page, pas de son index : `_ridePages` peut se décaler
      // (page masquée à la main, page conditionnelle insérée/retirée en fin
      // de liste — voir `_ridePages`), et sans cette clé Flutter réutilisait
      // l'Element de l'index sorti et rentré pour une page différente. Une
      // page de tours héritait alors du `_selectedIndex` d'une autre page de
      // tours (ou de tours de col) qui avait occupé le même index avant elle.
      key: ObjectKey(page),
      // `index == _page` : cette entrée est-elle celle sous les yeux, ou une
      // voisine que le `PageView` garde construite en cache pendant qu'on est
      // ailleurs ? `LapListBody` s'en sert pour revenir au tour en cours
      // chaque fois qu'on revient sur cette page, quel que soit le sort de
      // son `Element` entre-temps.
      visible: index == _page,
      page: page,
      sources: _sources,
      radar: _preset.sensors.radar ? _radar : null,
      battery: _battery,
      // Les pages rangées derrière le menu se retrouvent depuis n'importe
      // laquelle : elles n'appartiennent à aucune en particulier.
      menuPages: _menuPages,
      onOpenMenuPage: _setMenuPage,
      // Sans carte, il n'y a aucune page à qui adresser un itinéraire : les deux
      // commandes disparaissent plutôt que de répondre « non ».
      onChooseRoute: _preset.hasMap ? _chooseRoute : null,
      onClearRoute: _preset.hasMap ? _clearRoute : null,
      // Sans carte, il n'y a personne pour s'endormir : `_sleep` ramènerait le
      // cycliste vers une page qui n'existe pas et n'appellerait `requestSleep`
      // sur aucun contrôleur.
      onSleep: _preset.hasMap ? _sleep : null,
      // Même raison : sans carte, il n'y a rien à archiver. `_offline` dit
      // lui-même si un tracé est effectivement suivi (`supported`).
      offlineMap: _preset.hasMap ? _offline : null,
      onDownloadOffline: _preset.hasMap ? _downloadOffline : null,
      // La commande n'apparaît que si un capteur connecté sait effectivement se
      // calibrer : évalué à chaque rendu, donc juste dès que le capteur répond.
      onCalibratePower:
          powerCalibrationAvailable(widget.hub) ? _calibratePower : null,
      // Sans rapport avec la carte : un programme d'entraînement se démarre
      // aussi bien sur home-trainer.
      onStartWorkout: _chooseWorkout,
      onStopWorkout: widget.recorder.activeWorkout != null ? _stopWorkout : null,
      debugClimbActive: _debugClimbActive,
      onSimulateClimb: _toggleDebugClimb,
      // Même col que la pastille et la carte dépliée (voir [_debugClimb]) :
      // sans lui, `ClimbProfileCard` restait aveugle au col de démonstration
      // et affichait « Aucun col en cours » pendant qu'il tournait au-dessus.
      debugClimb: _debugClimb,
      debugClimbProfile: _debugClimbActive ? _debugClimbProfile : null,
      onLeaveRide: _leaveRide,
      onGridMeasured: widget.onGridMeasured,
      // Absente plutôt que grisée quand la retirer viderait le défilement de
      // toute page hors carte — même convention que les autres commandes qui
      // n'auraient que « non » à répondre (`onClearRoute`, `onDownloadOffline`).
      onHidePage: _canHide(page) ? () => _hidePage(page) : null,
    );
  }

  /// Une gouttière, c'est-à-dire deux choses qui se partagent le même bord :
  /// la bande de changement de page, qui n'existe que sur la carte, et la jauge
  /// radar, qui est là sur toutes les pages.
  ///
  /// Empilées plutôt que juxtaposées — se partager vingt-deux points en
  /// donnerait onze à chacune, et onze points ne se visent pas à vélo. Quand le
  /// radar alerte, c'est lui qu'on voit : la bande garde ses gestes et efface
  /// son repère.
  ///
  /// La bande de gestes n'existe **que sur la page carte**, où le `PageView` est
  /// hors du test de touche : ailleurs, tout l'écran fait déjà défiler.
  Widget _gutter(RadarGaugeSide side, double bandHeight) {
    final left = side == RadarGaugeSide.left;

    return Positioned(
      key: ValueKey('gouttiere-${side.name}'),
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: bandHeight,
      child: ValueListenableBuilder<RadarView>(
        valueListenable: _radar,
        builder: (context, radar, _) => SizedBox(
          width: RadarSideGauge.width,
          child: Stack(
            children: [
              if (_overlay)
                Positioned.fill(child: RadarSideGauge(view: radar, side: side)),
              if (_onMap)
                Positioned(
                  left: left ? 0 : null,
                  right: left ? null : 0,
                  top: 0,
                  bottom: 0,
                  child: MapEdgeHandle(
                    direction: left ? -1 : 1,
                    onStep: _stepPage,
                    // Le repère ne s'efface que devant une jauge : sans
                    // habillage, la gouttière n'a rien d'autre à montrer, et
                    // faire disparaître le seul repère de changement de page
                    // au moment où une voiture remonte se lirait comme un
                    // écran gelé.
                    showBar: !_overlay || !radar.isAlerting,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
