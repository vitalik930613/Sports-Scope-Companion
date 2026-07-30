import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/rider_profile.dart';
import '../account/rider_profile_store.dart';
import '../account/site_session.dart';
import '../ble/sensor_hub.dart';
import '../navigation/navigation_target.dart';
import '../navigation/screen_dimmer.dart';
import '../recording/ride_recorder.dart';
import 'nav_state.dart';
import 'navigation_web_view.dart';
import 'pages/ride_summary_page.dart';
import 'ride_pages.dart';
import 'screen_policy.dart';
import 'widgets/map_edge_handle.dart';
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
    this.baseUrl = sportsScopeBaseUrl,
  });

  final NavigationTarget target;
  final SensorHub hub;

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

  final _pages = PageController();

  /// La page affichée. Suit le défilement dès qu'il passe la moitié, pour que
  /// les pastilles ne restent pas en retard sur ce qu'on voit.
  int _pageIndex = 0;

  /// Un défilement est-il en cours ? Sert à ne basculer la carte en « vivante »
  /// qu'une fois le geste terminé : le faire à mi-glissé couperait le geste au
  /// milieu, et le défilement s'arrêterait en travers.
  bool _scrolling = false;

  /// La carte a-t-elle la main sur les gestes ? Vrai seulement quand elle est
  /// affichée et posée. Le [PageView] est alors entièrement hors du test de
  /// touche — sans quoi son détecteur, qui couvre toute la surface, volerait à
  /// MapLibre le glissé dont la carte a besoin pour se déplacer.
  bool get _mapLive => _pageIndex == 0 && !_scrolling;

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

    _web = NavigationWebController(
      hub: widget.hub,
      target: widget.target,
      baseUrl: widget.baseUrl,
      onMessage: _onPageMessage,
      onPageFinished: _onPageFinished,
    );
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
    _web.setOccluded(_pageIndex != 0);
    // Une page anonyme n'est pas une panne mais une navigation dégradée
    // (pas d'itinéraires, fond de carte par défaut, POI muets) : on le
    // note pour que l'écran des capteurs puisse le dire avant la sortie.
    _checkSession();
  }

  Future<void> _checkSession() async {
    await widget.session.record(await _web.probeSession());
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

  /// Emmène le cycliste sur une page, d'où qu'en vienne la demande : glissé sur
  /// le bandeau, pastille, poignée du bord, ou plus tard retour automatique à
  /// l'approche d'un virage.
  void _goToPage(int page) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(
      page.clamp(0, RidePage.count - 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int page) {
    setState(() => _pageIndex = page);
    // La page web n'est plus regardée : qu'elle cesse d'animer. Elle continue
    // en revanche de suivre la position, de compter les virages et de publier
    // son état — c'est tout l'intérêt de la garder montée.
    _web.setOccluded(page != 0);
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
        if (_pageIndex != 0) {
          _goToPage(0);
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
            // sont là. La page 0 est vide : c'est la carte qu'on voit à travers.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: bandHeight,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: IgnorePointer(
                  ignoring: _mapLive,
                  child: PageView(
                    controller: _pages,
                    physics: physicsForMap(mapLive: _mapLive),
                    onPageChanged: _onPageChanged,
                    children: [
                      const SizedBox.shrink(),
                      RideSummaryPage(recorder: widget.recorder, nav: _nav),
                    ],
                  ),
                ),
              ),
            ),
            // La poignée du bord droit, seulement sur la carte : ailleurs, tout
            // l'écran ramène déjà à la carte d'un glissé.
            if (_pageIndex == 0)
              Positioned(
                right: 0,
                top: 0,
                bottom: bandHeight,
                child: MapEdgeHandle(onOpen: () => _goToPage(1)),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RideBottomBand(
                hub: widget.hub,
                recorder: widget.recorder,
                nav: _nav,
                pageIndex: _pageIndex,
                onGoToPage: _goToPage,
              ),
            ),
          ],
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
