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
import '../navigation/navigation_picker_sheet.dart';
import '../navigation/navigation_target.dart';
import '../navigation/route_catalog_store.dart';
import '../navigation/screen_dimmer.dart';
import '../phone/rider_compass.dart';
import '../recording/ride_recorder.dart';
import '../ui/offline_download_dialog.dart';
import '../ui/power_calibration_dialog.dart';
import 'auto_return_policy.dart';
import 'climb_debug_data.dart';
import 'climb_profile.dart';
import 'native_turn_alerts.dart';
import 'nav_state.dart';
import 'navigation_web_view.dart';
import 'offline_map_state.dart';
import 'pages/dashboard_page.dart';
import 'radar_alert_sound.dart';
import 'radar_severity.dart';
import 'radar_wake_policy.dart';
import 'ride_pages.dart';
import 'route_climbs.dart';
import 'screen_policy.dart';
import 'turn_proximity.dart';
import 'widgets/climb_badge.dart';
import 'widgets/compass_badge.dart';
import 'widgets/climb_profile_overlay.dart';
import 'widgets/map_edge_handle.dart';
import 'widgets/map_swipe_zone.dart';
import 'widgets/notch_band.dart';
import 'widgets/radar_frame.dart';
import 'widgets/radar_side_gauge.dart';
import 'widgets/radar_wake_page.dart';
import 'widgets/ride_bottom_band.dart';
import 'widgets/ride_page_flash.dart';

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
    required this.recorder,
    this.compass,
    required this.session,
    required this.riderProfile,
    required this.trainingBudget,
    required this.routes,
    this.onGridMeasured,
    this.baseUrl = sportsScopeBaseUrl,
  });

  final NavigationTarget target;

  /// Le profil de sortie : les pages, le bandeau, les capteurs, le radar.
  /// Choisi au départ et figé pour la durée de la sortie — changer de tableau
  /// de bord en roulant n'a aucun usage et coûterait de reconstruire la pile.
  final RidePreset preset;

  final SensorHub hub;

  /// Les itinéraires du compte, pour en choisir un autre en pleine sortie. Le
  /// même magasin que l'écran des capteurs : son cache est ce qui rend le choix
  /// possible là où le réseau manque, c'est-à-dire sur la route.
  final RouteCatalogStore routes;

  /// L'enregistrement en cours, pour le bandeau et les pages de données. La
  /// coquille ne le pilote pas — il vit au-dessus des écrans et survit à la
  /// navigation.
  final RideRecorder recorder;

  /// La boussole du téléphone. La coquille est la SEULE à l'allumer, et
  /// seulement le temps de la sortie : un magnétomètre branché en permanence
  /// réveille le processeur pour une flèche que personne ne regarde. Nulle sur
  /// un appareil sans magnétomètre, dans un test, ou quand le profil l'a coupée.
  final RiderCompass? compass;

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

  /// Le profil du col en cours, poussé une fois par col (voir
  /// climb_profile.dart). Sans carte, personne ne l'alimente ni ne l'écoute —
  /// même sort que [_nav].
  final _climbProfile = ClimbProfileNotifier();

  /// La liste des cols du tracé en cours, poussée une fois par tracé (voir
  /// route_climbs.dart). Sans carte, personne ne l'alimente ni ne l'écoute —
  /// même sort que [_nav] et [_climbProfile].
  final _routeClimbs = RouteClimbsNotifier();

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
  /// pas d'horloge ni de plusieurs sources concurrentes à départager. Repliée
  /// par défaut et à chaque nouveau col (voir _onPageMessage) : un col qui
  /// s'ouvre grand tout seul recouvrirait la carte au moment précis où le
  /// cycliste a le plus besoin de voir la route devant lui.
  final _climbExpanded = ValueNotifier<bool>(false);

  /// Un col de démonstration, affiché par-dessus la sortie réelle (carte,
  /// bandeau, radar) — voir le bouton « Simuler un col » du menu d'actions.
  /// Juger la pastille et le graphique dans une vraie sortie, sans attendre
  /// de grimper un col, est ce que la page isolée `ClimbDebugPage` ne permet
  /// pas : elle n'a ni carte ni radar à côté.
  bool _debugClimbActive = false;

  /// Fixe et pas animé : contrairement à `ClimbDebugPage` (qui a son propre
  /// curseur), ce bouton sert à juger la *composition* avec le reste de la
  /// sortie, pas le mouvement du profil.
  static const _debugClimbRatio = 0.42;

  late final _debugClimbProfile = debugClimbProfile();

  void _toggleDebugClimb() {
    setState(() => _debugClimbActive = !_debugClimbActive);
    if (!_debugClimbActive) _climbExpanded.value = false;
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

  /// Le défilement du moment : les pages toujours-défilantes, puis les pages
  /// conditionnelles actives, **toujours en fin de liste**. Cet ordre est ce
  /// qui garde [RidePreset.mapPageIndex] valable tel quel : une page qui
  /// apparaît ou disparaît ici ne décale jamais la carte ni les pages qui la
  /// précèdent.
  List<RidePageSpec> get _ridePages => [
        ..._baseRidePages,
        for (final page in _conditionalPages)
          if (_activeConditional.contains(page)) page,
      ];

  /// Les pages rangées derrière le menu du moment : les pages sans condition,
  /// et les pages conditionnelles **inactives** — une page active est dans
  /// [_ridePages], pas ici, elle n'a donc pas besoin d'être allée chercher.
  List<RidePageSpec> get _menuPages => [
        for (final page in _baseMenuPages)
          if (!_conditionalPages.contains(page) || !_activeConditional.contains(page)) page,
      ];

  /// La page ouverte depuis le menu, index dans [_menuPages]. `null` la plupart
  /// du temps — c'est une page qu'on va chercher, pas une page où l'on est.
  int? _menuPage;

  int get _pageCount => _ridePages.length;

  /// La page affichée, index dans le défilement.
  int get _page => pageOf(_rawPage, count: _pageCount);

  /// Où est la carte dans le défilement, `null` quand le profil n'en a pas.
  int? get _mapPage => _preset.mapPageIndex;

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
  late final AutoReturnPolicy _autoReturn;
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

  /// Boutons distants (D-Fly du Di2) : squelette de câblage en attente du
  /// décodeur — voir `RemoteButtonSample` (`ble/samples.dart`) et le TODO dans
  /// `ble/decoders/di2.dart`. Personne n'émet encore cet échantillon.
  StreamSubscription<SensorSample>? _remoteButtonSub;

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

  /// Ce qui décide de rallumer l'écran pour une voiture, et de le rendre à la
  /// veille ensuite.
  late final RadarWakePolicy _radarWake;

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

    // Même garde que pour le radar : un profil qui écarte le Di2 (vélo prêté,
    // boîtier de l'autre vélo) ne doit pas laisser ses boutons piloter le
    // tableau de bord. `_stepPage` marque déjà le geste comme manuel
    // (`_autoMoves == 0` dans `_onPageChanged`), donc une pression suspend le
    // retour auto exactement comme un glissé de bandeau.
    if (_preset.sensors.gears) {
      _remoteButtonSub = widget.hub.samples.listen((sample) {
        if (sample is! RemoteButtonSample) return;
        _stepPage(sample.button == RemoteButton.next ? 1 : -1);
      });
    }

    // La boussole ne sert qu'avec une carte — c'est la page qui consomme le cap
    // — et ne mesure rien tant qu'on n'a pas comparé ses caps à la course GPS.
    if (_preset.sensors.compass && _preset.hasMap) widget.compass?.start();

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
      climbProfile: _preset.hasMap ? _climbProfile : null,
    );

    // Deux déclencheurs pour une seule décision : le pont pour les fronts, le
    // temps pour les délais. Le tic sert aussi au maintien du réveil radar.
    _nav.addListener(_decideReturn);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _decideReturn();
      _updateRadarWake();
      _checkNativeTurnAlert();
      _updateConditionalPages();
      // Même source que le chien de garde (`recorder.lastFix`) et même
      // conséquence assumée : hors enregistrement la boussole n'a aucune course
      // à laquelle se comparer, donc elle ne se validera pas.
      widget.compass?.addFix(widget.recorder.lastFix);
      final heading = widget.compass?.correctedHeadingDeg;
      _compassReading.value =
          heading == null ? null : (heading, widget.compass!.isTrusted);
      // Le pont ne se marque « sale » tout seul que sur une trame BLE
      // (`SensorBridge._dirty`) : sans ça, le cap forcé ne partirait qu'une
      // fois, au tap, et la flèche resterait figée sur cette valeur au lieu
      // de suivre la boussole qui continue de tourner.
      if (widget.compass?.forced ?? false) _web?.bridge.pushNow();
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
        if (_conditionMet(page.menuCondition!)) page,
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

    setState(() => _activeConditional = next);

    if (autoOpen != null) {
      // Anime, et ferme au passage la page du menu qu'on vient déjà de fermer
      // — sans effet ici, mais c'est le seul chemin qui sait aussi recalculer
      // l'index brut le plus proche.
      _goToPage(_ridePages.indexOf(autoOpen), auto: true);
      return;
    }

    final keepIndex = currentSpec == null ? -1 : _ridePages.indexOf(currentSpec);
    if (keepIndex != -1) {
      // La page regardée existe encore : on ne fait que corriger l'index brut
      // pour la nouvelle taille du catalogue, sans la moindre animation — rien
      // ne doit bouger à l'écran.
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

    // La page regardée vient de disparaître du défilement (sa condition a
    // cessé pendant qu'on la lisait) : retour à la carte, comme tout autre
    // retour automatique.
    _goToPage(_mapPage ?? 0, auto: true);
  }

  bool _conditionMet(PageMenuCondition condition) => switch (condition) {
        PageMenuCondition.routeActive => _nav.value?.onRoute == true,
        PageMenuCondition.descending => _updateDescending(),
        PageMenuCondition.nearCol => _nearCol(),
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

  bool _nearCol() {
    final nav = _nav.value;
    // Hors trace, la position à laquelle la page accroche le tracé (et donc le
    // col qu'elle désigne) n'a plus rien de fiable — un GPS instable avant de
    // rejoindre l'itinéraire peut y faire retomber n'importe où, y compris en
    // plein milieu d'un col qu'on n'aborde pas.
    if (nav == null || nav.offRoute) return false;
    if (nav.climb != null) return true;

    final climbs = _routeClimbs.value;
    final traveled = climbs == null ? null : traveledDistM(climbs, nav);
    if (climbs == null || traveled == null) return false;

    return climbs.climbs.any((climb) {
      if (climbStatusOf(climb, traveled) != ClimbStatus.upcoming) return false;
      return climb.startDistM - traveled <= _nearColLeadM;
    });
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
  void _stepPage(int direction) => _animateTo(_rawPage + direction);

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
        // Front descendant du col : « il y avait un climb, il n'y en a
        // plus ». Comparé AVANT d'accepter le nouveau message, pas après —
        // sinon les deux valent toujours la nouvelle. Un profil laissé en
        // place après la fin du col redessinerait le dernier col fini sur un
        // col suivant qui n'a pas encore poussé le sien (fenêtre de quelques
        // centaines de ms entre climb_profile et le premier nav.climb, cf.
        // climb_profile.dart).
        final hadClimb = _nav.value?.climb != null;
        _nav.accept(message);
        final hasClimb = _nav.value?.climb != null;
        if (hadClimb != hasClimb) {
          // Isole la montée dans son propre tour de la série `cols` — sans
          // effet si aucune page ou bouton du profil ne la déclare
          // (`RideRecorder.markLap`, no-op sur une série inconnue).
          widget.recorder.markLap(climbLapSeries);
        }
        if (hadClimb && !hasClimb) {
          _climbProfile.reset();
          _climbExpanded.value = false;
        }
      case 'climb_profile':
        _climbProfile.accept(message);
      case 'route_climbs':
        _routeClimbs.accept(message);
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
    unawaited(_remoteButtonSub?.cancel());
    // Le magnétomètre s'éteint avec la sortie : c'est le seul capteur de ce
    // dossier qui coûterait de la batterie une fois l'écran refermé.
    unawaited(widget.compass?.stop());
    _nav.removeListener(_decideReturn);
    _radar.removeListener(_onRadar);
    _radar.dispose();
    _mutedRadar.dispose();
    _radarSound.dispose();
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
    _routeClimbs.dispose();
    _climbExpanded.dispose();
    _offline.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bandHeight = RideBottomBand.heightFor(context);
    final webView = _webView;

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
            if (_menuPage case final index?)
              Positioned(
                key: const ValueKey('menu'),
                left: 0,
                right: 0,
                top: 0,
                bottom: bandHeight,
                child: DashboardPage(
                  page: _menuPages[index],
                  sources: _sources,
                  radar: _preset.sensors.radar ? _radar : null,
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
                  onClose: () => _setMenuPage(null),
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
                radar: _preset.sensors.radar ? _radar : null,
                onSleep: _preset.hasMap ? _sleep : null,
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
              child: ValueListenableBuilder<NavState?>(
                valueListenable: _nav,
                builder: (context, nav, _) {
                  // Le col simulé prime sur le vrai : c'est un banc d'essai,
                  // pas un second col qui s'ajouterait au premier.
                  final climb = _debugClimbActive
                      ? debugClimbFor(_debugClimbProfile, _debugClimbRatio)
                      : nav?.climb;
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
                  return ValueListenableBuilder<NavState?>(
                    valueListenable: _nav,
                    builder: (context, nav, _) {
                      final climb = _debugClimbActive
                          ? debugClimbFor(_debugClimbProfile, _debugClimbRatio)
                          : nav?.climb;
                      if (climb == null) return const SizedBox.shrink();
                      return ValueListenableBuilder<ClimbProfile?>(
                        valueListenable: _climbProfile,
                        builder: (context, profile, _) => ClimbProfileOverlay(
                          climb: climb,
                          profile: _debugClimbActive
                              ? _debugClimbProfile
                              : profile,
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
      page: page,
      sources: _sources,
      radar: _preset.sensors.radar ? _radar : null,
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
      debugClimbActive: _debugClimbActive,
      onSimulateClimb: _toggleDebugClimb,
      onLeaveRide: _leaveRide,
      onGridMeasured: widget.onGridMeasured,
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
