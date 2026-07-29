import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/rider_profile.dart';
import '../account/rider_profile_store.dart';
import '../account/site_session.dart';
import '../ble/sensor_hub.dart';
import '../navigation/navigation_target.dart';
import '../navigation/screen_dimmer.dart';
import 'nav_state.dart';
import 'navigation_web_view.dart';

/// La coquille d'une sortie : ce qui appartient à l'écran, pas à la page web.
///
/// Elle possède le plein écran, le rétroéclairage, les zones obstruées et le
/// bouton retour ; la navigation web, elle, vit dans un [NavigationWebController]
/// créé une seule fois ici et qui lui survit. Ce partage prépare le tableau de
/// bord : des pages de données natives viendront se poser par-dessus la carte
/// sans jamais démonter le WebView.
class RideShellPage extends StatefulWidget {
  const RideShellPage({
    super.key,
    required this.target,
    required this.hub,
    required this.session,
    required this.riderProfile,
    this.baseUrl = sportsScopeBaseUrl,
  });

  final NavigationTarget target;
  final SensorHub hub;

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

  /// Ce que la page dit de la navigation en cours. Alimente le tableau de bord,
  /// et surtout le retour automatique sur la carte à l'approche d'un virage.
  final _nav = NavStateNotifier();

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
    _screen.restore();
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
  /// est exactement le cas ici.
  Future<void> _publishInsets() async {
    if (!mounted) return;
    await _web.pushInsets(MediaQuery.viewPaddingOf(context));
  }

  @override
  void didChangeMetrics() {
    // Rotation, écran partagé : les zones obstruées changent de place.
    _publishInsets();
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
        if (message['state'] == 'dimmed') {
          _screen.dim();
        } else {
          _screen.restore();
        }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Le bouton retour rend d'abord la main à l'historique de la page (une
      // dialogue ouverte, un panneau) avant de quitter la navigation.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
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
        body: NavigationWebView(controller: _web),
      ),
    );
  }
}
