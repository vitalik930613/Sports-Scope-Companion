import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../ble/sensor_hub.dart';
import 'navigation_target.dart';
import 'sensor_bridge.dart';

/// La navigation de sports-scope, affichée telle quelle.
///
/// Choix assumé : on n'a pas réécrit les ~8 000 lignes de la navigation web
/// (carte, virages, cols, POI, reroutage, tuiles hors-ligne). L'appli l'affiche
/// dans un WebView et lui apporte ce que le navigateur ne sait pas faire — les
/// capteurs BLE. Une seule implémentation de la navigation à faire évoluer.
///
/// La page web est une PWA : son service worker la sert hors ligne une fois
/// visitée, et ses archives de tuiles restent valables. C'est ce qui rend ce
/// montage viable sur la route, là où le réseau tombe.
class NavigationPage extends StatefulWidget {
  const NavigationPage({
    super.key,
    required this.target,
    required this.hub,
    this.baseUrl = sportsScopeBaseUrl,
  });

  final NavigationTarget target;
  final SensorHub hub;
  final String baseUrl;

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late final WebViewController _controller;
  late final SensorBridge _bridge;

  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Plein écran, barres système comprises : sur un guidon, chaque centimètre
    // de carte compte, et les barres d'Android n'ont rien à y faire. `sticky`
    // les fait réapparaître le temps d'un balayage depuis le bord puis les
    // remasque — sans quoi un geste involontaire les laisserait à l'écran pour
    // le reste de la sortie.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('SportsScopeCompanion',
          onMessageReceived: _onPageMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageFinished: (_) {
          // La page peut avoir été rechargée (retour de veille, perte de
          // réseau) : on republie l'état plutôt que d'attendre une trame.
          _bridge.pushNow();
        },
        onWebResourceError: (error) {
          // Seule l'erreur du document principal nous intéresse : une tuile ou
          // une image manquante hors ligne est normale et ne doit pas masquer
          // une navigation qui fonctionne.
          if (!error.isForMainFrame!) return;
          if (mounted) setState(() => _error = error.description);
        },
      ));

    // La console de la page remonte dans la sortie de `flutter run`. Sans ça,
    // une erreur JavaScript côté navigation serait invisible : le WebView
    // afficherait juste une carte figée, sans rien dire.
    _controller.setOnConsoleMessage((message) {
      debugPrint('[web] ${message.level.name}: ${message.message}');
    });

    _bridge = SensorBridge(
      hub: widget.hub,
      send: _controller.runJavaScript,
    )..start();

    _configureAndroid();
    _load();
  }

  /// La navigation a besoin de la position : sans ça, la page reste sur une
  /// carte figée. Le WebView ne demande rien de lui-même, il délègue à l'appli.
  void _configureAndroid() {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;

    // Rend la page inspectable depuis `chrome://inspect` du poste de dev —
    // DOM, réseau, points d'arrêt. Uniquement en debug : en release, ça
    // ouvrirait le contenu de l'appli à n'importe quel poste branché en USB.
    if (kDebugMode) AndroidWebViewController.enableDebugging(true);

    platform.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (request) async =>
          // `retain` : la page ne redemande pas à chaque reprise. La vraie
          // autorisation, elle, est celle d'Android, demandée avant d'ouvrir
          // cet écran.
          const GeolocationPermissionsResponse(allow: true, retain: true),
    );
    // Le média audio des instructions vocales ne doit pas attendre un geste.
    platform.setMediaPlaybackRequiresUserGesture(false);
  }

  void _load() {
    setState(() => _error = null);
    _controller.loadRequest(widget.target.url(baseUrl: widget.baseUrl));
  }

  /// Messages venus de la page.
  ///
  /// Un seul type pour l'instant : `ready`, que la page émet quand son pont est
  /// en place. Le protocole est volontairement en JSON typé — il grossira (mise
  /// en veille de l'écran, demande d'enregistrement), et un simple mot-clé
  /// deviendrait vite illisible.
  void _onPageMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is Map && decoded['type'] == 'ready') _bridge.pushNow();
    } catch (_) {
      // Message hors protocole : on l'ignore, la navigation prime.
    }
  }

  @override
  void dispose() {
    // Les barres reviennent en quittant la navigation : la page des capteurs
    // est un écran d'appli ordinaire, avec son horloge et ses gestes.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _bridge.dispose();
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
        if (await _controller.canGoBack()) {
          await _controller.goBack();
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
            if (_error == null) WebViewWidget(controller: _controller),
            if (_error == null && _progress < 100)
              LinearProgressIndicator(value: _progress / 100),
            if (_error != null) SafeArea(child: _errorView()),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Navigation indisponible',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            // Le hors-ligne ne marche qu'après une première visite : c'est le
            // service worker de la page qui la met en cache, pas l'appli.
            const Text(
              'Ouvre l\'itinéraire une fois avec du réseau : la page se met '
              'alors en cache et reste utilisable sur la route.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
