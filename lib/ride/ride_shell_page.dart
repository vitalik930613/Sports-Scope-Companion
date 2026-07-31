import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/rider_profile.dart';
import '../account/rider_profile_store.dart';
import '../account/site_session.dart';
import '../ble/sensor_hub.dart';
import '../navigation/navigation_picker_sheet.dart';
import '../navigation/navigation_target.dart';
import '../navigation/route_catalog_store.dart';
import '../navigation/screen_dimmer.dart';
import '../recording/ride_recorder.dart';
import 'auto_return_policy.dart';
import 'nav_state.dart';
import 'navigation_web_view.dart';
import 'pages/ride_summary_page.dart';
import 'radar_alert_sound.dart';
import 'radar_severity.dart';
import 'ride_pages.dart';
import 'screen_policy.dart';
import 'turn_proximity.dart';
import 'widgets/map_edge_handle.dart';
import 'widgets/radar_distance_badges.dart';
import 'widgets/radar_frame.dart';
import 'widgets/radar_side_gauge.dart';
import 'widgets/ride_bottom_band.dart';

/// La coquille d'une sortie : ce qui appartient à l'écran, pas à la page web.
///
/// Elle possède le plein écran, le rétroéclairage, les zones obstruées, le
/// bouton retour et les pages du tableau de bord ; la navigation web, elle, vit
/// dans un [NavigationWebController] créé une seule fois ici et qui lui survit.
///
/// **Le WebView reste monté, mesuré et peint en permanence**, au fond d'une
/// pile, et les pages de données glissent par-dessus. Ce n'est pas une commodité
/// de mise en page : une vue plateforme démontée emporte avec elle le pointeur
/// de virage, la progression sur le tracé, l'état de reroutage et les tuiles
/// MapLibre en mémoire — soit un rechargement complet en pleine sortie. Une vue
/// simplement sortie de la liste de peinture, elle, se fait étrangler par
/// certaines surcouches constructeur, et la page cesse de suivre le cycliste.
/// Mesuré sur route avant d'être adopté (sonde M0, branche `m0-webview-probe`) :
/// 465 messages de navigation en sept minutes sous un voile opaque, sans un seul
/// rechargement.
///
/// Le prix, c'est une carte qui continue de composer derrière une page qu'on ne
/// regarde pas. D'où [NavigationWebController.setOccluded], qui prévient la page
/// de couper ses animations sans rien endormir.
class RideShellPage extends StatefulWidget {
  const RideShellPage({
    super.key,
    required this.target,
    required this.hub,
    required this.recorder,
    required this.session,
    required this.riderProfile,
    required this.routes,
    this.baseUrl = sportsScopeBaseUrl,
  });

  final NavigationTarget target;
  final SensorHub hub;

  /// Les itinéraires du compte, pour en choisir un autre en pleine sortie. Le
  /// même magasin que l'écran des capteurs : son cache est ce qui rend le choix
  /// possible là où le réseau manque, c'est-à-dire sur la route.
  final RouteCatalogStore routes;

  /// L'enregistrement en cours, pour le bandeau et la page d'effort. La coquille
  /// ne le pilote pas — il vit au-dessus des écrans et survit à la navigation.
  final RideRecorder recorder;

  /// Pas pour authentifier la page — le cookie du WebView s'en charge — mais
  /// pour tenir à jour ce que l'appli affiche de la session : la navigation est
  /// la page du site la plus souvent ouverte, donc le meilleur point d'écoute.
  final SiteSession session;

  /// Seuils et zones du cycliste. La page les récupère du site et les pousse
  /// ici : l'appli n'a aucun identifiant à présenter, elle ne peut pas les
  /// demander elle-même.
  final RiderProfileStore riderProfile;

  final String baseUrl;

  @override
  State<RideShellPage> createState() => _RideShellPageState();
}

class _RideShellPageState extends State<RideShellPage>
    with WidgetsBindingObserver {
  late final NavigationWebController _web;
  final _screen = ScreenDimmer();
  final _screenPolicy = ScreenPolicy();

  /// Ce que la page dit de la navigation en cours. Alimente le tableau de bord,
  /// et surtout le retour automatique sur la carte à l'approche d'un virage.
  final _nav = NavStateNotifier();

  final _pages = PageController(initialPage: rawPageOrigin);

  /// L'index brut du défilement, qui monte et descend sans borne pour que le
  /// catalogue tourne en boucle (voir [rawPageOrigin]). Suit le défilement dès
  /// qu'il passe la moitié, pour que les pastilles ne restent pas en retard sur
  /// ce qu'on voit.
  int _rawPage = rawPageOrigin;

  /// La page affichée, celle du catalogue.
  RidePage get _page => RidePage.values[pageOf(_rawPage)];

  /// Un défilement est-il en cours ? Sert à ne basculer la carte en « vivante »
  /// qu'une fois le geste terminé : le faire à mi-glissé couperait le geste au
  /// milieu, et le défilement s'arrêterait en travers.
  bool _scrolling = false;

  /// Le retour automatique sur la carte, et la restitution de la page ensuite.
  final _alerts = RideAlertSource();
  final _autoReturn = AutoReturnPolicy();
  static const _proximity = TurnProximity();

  /// L'horloge du retour automatique. Le front d'une alerte arrive par le pont,
  /// mais « rendre la page une fois le calme revenu » n'est piloté que par le
  /// temps qui passe : sans ce tic, la page ne reviendrait qu'au prochain
  /// message, c'est-à-dire jamais si le GPS a décroché.
  Timer? _tick;

  /// Le cycliste a-t-il changé de page de sa main depuis la dernière décision ?
  /// C'est ce qui lui donne le dernier mot sur la politique.
  bool _userMoved = false;

  /// Nombre de déplacements en cours décidés par la politique. Un compteur et
  /// pas un booléen : deux animations peuvent se chevaucher, et retomber à
  /// « c'est le cycliste » entre les deux ferait annuler le retour par le
  /// retour lui-même.
  int _autoMoves = 0;

  /// Le radar, prêt à dessiner et capable de se périmer tout seul.
  late final RadarViewNotifier _radar;

  /// Et sa voix : le seul élément du tableau de bord qui n'attende pas qu'on
  /// regarde l'écran.
  final _radarVoice = RadarAlertVoice();
  final _radarSound = RadarAlertPlayer();

  /// La carte a-t-elle la main sur les gestes ? Vrai seulement quand elle est
  /// affichée et posée. Le [PageView] est alors entièrement hors du test de
  /// touche — sans quoi son détecteur, qui couvre toute la surface, volerait à
  /// MapLibre le glissé dont la carte a besoin pour se déplacer.
  bool get _mapLive => _page == RidePage.navigation && !_scrolling;

  /// Construit une fois : un changement de page ne doit pas reconstruire l'arbre
  /// du WebView. Le widget est bête et le contrôleur porte tout l'état, mais une
  /// instance identique évite jusqu'au diff.
  late final Widget _webView = NavigationWebView(controller: _web);

  @override
  void initState() {
    super.initState();

    // Plein écran, barres système comprises : sur un guidon, chaque centimètre
    // de carte compte, et les barres d'Android n'ont rien à y faire. `sticky`
    // les fait réapparaître le temps d'un balayage depuis le bord puis les
    // remasque — sans quoi un geste involontaire les laisserait à l'écran pour
    // le reste de la sortie.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);

    _radar = RadarViewNotifier(widget.hub.latestRadar);
    _radar.addListener(_speakRadar);
    // Chargés maintenant : quand une voiture arrivera, il ne sera plus temps
    // d'ouvrir des fichiers.
    unawaited(_radarSound.warmUp());

    _web = NavigationWebController(
      hub: widget.hub,
      target: widget.target,
      baseUrl: widget.baseUrl,
      onMessage: _onPageMessage,
      onPageFinished: _onPageFinished,
    );

    // Deux déclencheurs pour une seule décision : le pont pour les fronts, le
    // temps pour les délais.
    _nav.addListener(_decideReturn);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _decideReturn());
  }

  void _onPageFinished() {
    _publishInsets();
    // Une page fraîchement chargée n'est pas en veille : son voile noir a
    // disparu avec son état. Sans cette remise à zéro, un rechargement en
    // pleine veille laisserait une carte allumée à 1 % de luminosité. Si
    // elle se rendort, elle le redira.
    _applyScreen(_screenPolicy.pageReloaded());
    // Elle ne sait pas non plus qu'elle est peut-être masquée par une page de
    // données : on le lui redit, sinon elle animerait dans le vide.
    _web.setOccluded(_page != RidePage.navigation);
    // Elle a pu recharger, ou ouvrir un autre tracé : l'arrivée qu'on avait déjà
    // vue ne compte plus, celle qui viendra sera une nouvelle arrivée.
    _alerts.reset();
    _autoReturn.reset();
    // Une page anonyme n'est pas une panne mais une navigation dégradée
    // (pas d'itinéraires, fond de carte par défaut, POI muets) : on le
    // note pour que l'écran des capteurs puisse le dire avant la sortie.
    _checkSession();
  }

  /// Le radar vient de changer d'état : y a-t-il quelque chose à dire ?
  void _speakRadar() {
    if (_radarVoice.read(_radar.value.severity) case final cue?) {
      _radarSound.play(cue);
    }
  }

  /// Faut-il ramener le cycliste sur la carte, ou lui rendre sa page ?
  ///
  /// La position vient de l'enregistreur et non d'un abonnement à part : c'est
  /// le seul flux GPS de l'appli, et en ouvrir un deuxième pour le chien de
  /// garde coûterait un service au premier plan de plus, avec sa notification
  /// qui parlerait d'un enregistrement inexistant. Conséquence assumée : hors
  /// enregistrement, le chien de garde n'a pas de position et le retour
  /// automatique repose entièrement sur le pont.
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

    final decision = _autoReturn.update(
      now: now,
      currentPage: _page,
      alert: alert,
      userMoved: _userMoved,
    );
    _userMoved = false;

    if (decision.goTo case final page?) _goToPage(page, auto: true);
  }

  Future<void> _checkSession() async {
    await widget.session.record(await _web.probeSession());
  }

  /// Changer de tracé sans quitter la sortie.
  ///
  /// Le besoin est celui de la route : on part sur un itinéraire, on décide de
  /// couper, de rallonger, ou de rentrer. Jusqu'ici il fallait sortir de la
  /// navigation et tout relancer — donc perdre la carte et son démarrage.
  ///
  /// La même feuille qu'au départ : elle sait déjà lire le catalogue en cache,
  /// coller un lien, et proposer la reprise. Le sélecteur ne fait que rendre
  /// une cible ; l'ouvrir appartient à la coquille, qui possède le WebView.
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
  /// progression avec elle. On ne la retrouve pas en rechoisissant l'itinéraire,
  /// on la refait.
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

  /// Charge un autre tracé dans la page déjà montée.
  ///
  /// L'état de navigation est remis à zéro tout de suite : celui du tracé qu'on
  /// quitte ne dit plus rien de celui qui arrive, et le laisser en place ferait
  /// afficher un virage périmé — voire proposer de retirer un itinéraire qui
  /// n'existe plus — pendant les secondes du chargement. Les alertes et le
  /// retour automatique, eux, sont déjà repris à la fin du chargement
  /// (`_onPageFinished`).
  void _openTarget(NavigationTarget target) {
    _nav.reset();
    _web.openTarget(target);
    // Sur la carte : c'est là que le chargement se voit, et c'est ce qu'on veut
    // regarder juste après avoir choisi où aller.
    _goToPage(RidePage.navigation);
  }

  /// Republie les zones obstruées de l'écran vers la page.
  ///
  /// `viewPadding` et non `padding` : la première garde la hauteur de
  /// l'obstruction physique même quand les barres système sont masquées, ce qui
  /// est exactement le cas ici. Le bas, lui, est retiré par [webInsetsFor] :
  /// depuis que le bandeau natif occupe cette zone, le WebView ne la touche
  /// plus.
  Future<void> _publishInsets() async {
    if (!mounted) return;
    await _web.pushInsets(webInsetsFor(MediaQuery.viewPaddingOf(context)));
  }

  @override
  void didChangeMetrics() {
    // Rotation, écran partagé : les zones obstruées changent de place, et avec
    // elles la hauteur du bandeau, donc le cadre de la carte.
    _publishInsets();
  }

  /// Emmène le cycliste sur une page nommée : pastille, bouton retour, ou plus
  /// tard retour automatique à l'approche d'un virage. Par le chemin le plus
  /// court dans la boucle, jamais par le tour complet.
  void _goToPage(RidePage page, {bool auto = false}) =>
      _animateTo(rawPageFor(page.index, from: _rawPage), auto: auto);

  /// Avance ou recule d'une page, sans se soucier de laquelle : c'est ce que
  /// demandent les bandes du bord, qui parlent en gestes et pas en destinations.
  /// L'index brut n'ayant pas de bout, il n'y a rien à borner — la boucle est
  /// exactement là.
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
    // une page de données ne passe par aucun de nos appels, il ne se voit que
    // là.
    if (_autoMoves == 0) _userMoved = true;
    setState(() => _rawPage = rawPage);
    // La page web n'est plus regardée : qu'elle cesse d'animer. Elle continue
    // en revanche de suivre la position, de compter les virages et de publier
    // son état — c'est tout l'intérêt de la garder montée.
    final page = pageOf(rawPage);
    _web.setOccluded(page != RidePage.navigation.index);
    _applyScreen(_screenPolicy.movedTo(page));
  }

  /// Messages venus de la page.
  ///
  /// `ready` : la page annonce que son pont est en place.
  /// `screen` : elle entre ou sort de sa veille, et demande le rétroéclairage
  /// correspondant — ce qu'un navigateur ne sait pas faire lui-même.
  /// `nav` : où en est la navigation (virage, hors-trace, arrivée, col).
  /// `rider_profile` : les seuils du cycliste, relayés depuis le site.
  ///
  /// Le protocole est volontairement en JSON typé : il grossira, et un simple
  /// mot-clé deviendrait vite illisible.
  void _onPageMessage(Map<dynamic, dynamic> message) {
    switch (message['type']) {
      case 'ready':
        _web.bridge.pushNow();
      case 'nav':
        _nav.accept(message);
      case 'rider_profile':
        widget.riderProfile.record(RiderProfile.fromJson(message['profile']));
      case 'screen':
        _applyScreen(
          _screenPolicy.pageRequested(message['state'] == 'dimmed'),
        );
    }
  }

  /// N'appelle le réglage de luminosité que sur les transitions : la page peut
  /// redemander sa veille à chaque rechargement, et changer la luminosité
  /// globale du téléphone n'est pas une opération à répéter pour rien.
  void _applyScreen(bool changed) {
    if (!changed) return;
    if (_screenPolicy.dimmed) {
      _screen.dim();
    } else {
      _screen.restore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _nav.removeListener(_decideReturn);
    _radar.removeListener(_speakRadar);
    _radar.dispose();
    _radarSound.dispose();
    // Filet de sécurité : quitter la navigation en veille (bouton retour, page
    // qui plante) ne doit pas laisser l'appareil à 1 % de luminosité sur
    // l'écran des capteurs. La page le demande aussi de son côté, mais elle
    // n'est pas toujours en état de le faire.
    _screen.restore();
    // Les barres reviennent en quittant la navigation : la page des capteurs
    // est un écran d'appli ordinaire, avec son horloge et ses gestes.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _web.dispose();
    _nav.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bandHeight = RideBottomBand.heightFor(context);

    return PopScope(
      // Le bouton retour dépile dans l'ordre où le cycliste s'est éloigné de la
      // carte : d'abord la page de données, puis l'historique de la page web
      // (une dialogue ouverte, un panneau), et seulement alors la sortie.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_page != RidePage.navigation) {
          _goToPage(RidePage.navigation);
          return;
        }
        // Capturé avant l'attente : le WebView peut disparaître entre-temps.
        final navigator = Navigator.of(context);
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Pas de SafeArea autour de la carte : en immersif il n'y a plus de
        // barres à contourner, et l'encoche éventuelle est mieux occupée par la
        // carte que par une bande noire. Seul le message d'erreur, qui est du
        // texte à lire, garde ses marges.
        body: Stack(
          children: [
            // La carte, tout au fond et pour toute la sortie.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: bandHeight,
              child: _webView,
            ),
            // Les pages de données, dans le même cadre, opaques quand elles
            // sont là. La page « navigation » est vide : c'est la carte qu'on
            // voit à travers.
            //
            // Construite à la demande et sans fin, parce que le catalogue
            // tourne en boucle : l'index brut du défilement ne revient jamais
            // en arrière, c'est [pageOf] qui le replie sur les pages réelles.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: bandHeight,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: IgnorePointer(
                  ignoring: _mapLive,
                  child: PageView.builder(
                    controller: _pages,
                    physics: physicsForMap(mapLive: _mapLive),
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, rawPage) =>
                        switch (RidePage.values[pageOf(rawPage)]) {
                      RidePage.navigation => const SizedBox.shrink(),
                      RidePage.effort => RideSummaryPage(
                          recorder: widget.recorder,
                          nav: _nav,
                          riderProfile: widget.riderProfile,
                          onChooseRoute: _chooseRoute,
                          onClearRoute: _clearRoute,
                        ),
                    },
                  ),
                ),
              ),
            ),
            _gutter(RadarGaugeSide.left, bandHeight),
            _gutter(RadarGaugeSide.right, bandHeight),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RideBottomBand(
                hub: widget.hub,
                recorder: widget.recorder,
                nav: _nav,
                riderProfile: widget.riderProfile,
                page: _page,
                onGoToPage: _goToPage,
              ),
            ),
            // Le cadre par-dessus tout, bandeau compris : l'alerte n'appartient
            // pas à la carte, elle appartient à la sortie.
            Positioned.fill(
              child: ValueListenableBuilder<RadarView>(
                valueListenable: _radar,
                builder: (context, radar, _) =>
                    RadarFrame(severity: radar.severity),
              ),
            ),
            // Les mètres dans la bande de l'encoche, au-dessus du cadre : c'est
            // le chiffre qu'on va chercher, il ne doit être recouvert par rien.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ValueListenableBuilder<RadarView>(
                valueListenable: _radar,
                builder: (context, radar, _) => RadarDistanceBadges(view: radar),
              ),
            ),
          ],
        ),
      ),
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
  Widget _gutter(RadarGaugeSide side, double bandHeight) {
    final left = side == RadarGaugeSide.left;

    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: bandHeight,
      child: ValueListenableBuilder<RadarView>(
        valueListenable: _radar,
        builder: (context, radar, _) => SizedBox(
          width: MapEdgeHandle.width,
          child: Stack(
            children: [
              Positioned.fill(child: RadarSideGauge(view: radar, side: side)),
              if (_page == RidePage.navigation)
                Positioned.fill(
                  child: MapEdgeHandle(
                    direction: left ? -1 : 1,
                    onStep: _stepPage,
                    showBar: !radar.isAlerting,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final scrolling = switch (notification) {
      ScrollStartNotification() => true,
      ScrollEndNotification() => false,
      _ => _scrolling,
    };
    if (scrolling != _scrolling) setState(() => _scrolling = scrolling);
    // Faux : la notification continue son chemin, rien ici ne la consomme.
    return false;
  }
}
