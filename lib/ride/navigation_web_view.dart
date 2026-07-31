import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../account/site_session.dart';
import '../ble/sensor_hub.dart';
import '../navigation/navigation_target.dart';
import '../navigation/sensor_bridge.dart';

/// La page de navigation du site, et rien d'autre.
///
/// Séparé de la coquille ([RideShellPage]) parce que les deux n'ont pas la même
/// durée de vie : le contrôleur est créé une fois pour toute la sortie et
/// survit à chaque changement de page, là où le widget qui l'affiche peut être
/// reconstruit à volonté. Détruire le contrôleur coûterait la session de
/// navigation entière — pointeur de virage, progression, instance MapLibre et
/// ses tuiles en mémoire — donc un rechargement complet en pleine sortie.
///
/// Choix assumé : on n'a pas réécrit les ~8 000 lignes de la navigation web
/// (carte, virages, cols, POI, reroutage, tuiles hors-ligne). L'appli l'affiche
/// dans un WebView et lui apporte ce que le navigateur ne sait pas faire — les
/// capteurs BLE. Une seule implémentation de la navigation à faire évoluer.
///
/// La page web est une PWA : son service worker la sert hors ligne une fois
/// visitée, et ses archives de tuiles restent valables. C'est ce qui rend ce
/// montage viable sur la route, là où le réseau tombe.
class NavigationWebController {
  NavigationWebController({
    required this.hub,
    required NavigationTarget target,
    required this.baseUrl,
    required this.onMessage,
    required this.onPageFinished,
    // Le champ est privé parce qu'il change (`openTarget`), et un paramètre
    // nommé ne peut pas l'être : `this._target` serait refusé par le langage.
    // ignore: prefer_initializing_formals
  }) : _target = target {
    _build();
  }

  final SensorHub hub;
  final String baseUrl;

  NavigationTarget _target;

  /// Ce que la page affiche en ce moment. Change en pleine sortie quand le
  /// cycliste choisit un autre tracé ou retire le sien.
  NavigationTarget get target => _target;

  /// Messages venus de la page, déjà décodés. Le tri par `type` appartient à la
  /// coquille : c'est elle qui possède l'écran, la veille et les pages.
  final void Function(Map<dynamic, dynamic> message) onMessage;

  /// La page a fini de charger — y compris après un rechargement en pleine
  /// sortie (perte de réseau, retour arrière).
  final VoidCallback onPageFinished;

  late final WebViewController webView;
  late final SensorBridge bridge;

  /// Exposés en notifieurs plutôt qu'en `setState` : la barre de progression se
  /// redessine seule, sans reconstruire le [WebViewWidget] à chaque pourcent.
  final progress = ValueNotifier<int>(0);
  final error = ValueNotifier<String?>(null);

  void _build() {
    webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('SportsScopeCompanion',
          onMessageReceived: _onPageMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) => progress.value = value,
        onPageFinished: (_) {
          // La page peut avoir été rechargée (retour de veille, perte de
          // réseau) : on republie l'état plutôt que d'attendre une trame.
          bridge.pushNow();
          onPageFinished();
        },
        onWebResourceError: (e) {
          // Seule l'erreur du document principal nous intéresse : une tuile ou
          // une image manquante hors ligne est normale et ne doit pas masquer
          // une navigation qui fonctionne.
          if (!e.isForMainFrame!) return;
          error.value = e.description;
        },
      ));

    // La console de la page remonte dans la sortie de `flutter run`. Sans ça,
    // une erreur JavaScript côté navigation serait invisible : le WebView
    // afficherait juste une carte figée, sans rien dire.
    webView.setOnConsoleMessage((message) {
      debugPrint('[web] ${message.level.name}: ${message.message}');
    });

    bridge = SensorBridge(hub: hub, send: webView.runJavaScript)..start();

    _configureAndroid();
    load();
  }

  /// La navigation a besoin de la position : sans ça, la page reste sur une
  /// carte figée. Le WebView ne demande rien de lui-même, il délègue à l'appli.
  void _configureAndroid() {
    final platform = webView.platform;
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

  void load() {
    error.value = null;
    webView.loadRequest(_target.url(baseUrl: baseUrl));
  }

  /// Change de tracé en pleine sortie, **sur le contrôleur existant**.
  ///
  /// C'est un chargement de page, forcément : le tracé est choisi par l'URL et
  /// le site n'a pas d'autre porte d'entrée. Ce qui survit, c'est tout le reste
  /// — l'instance MapLibre et ses tuiles en mémoire, le pot de cookies, le pont
  /// des capteurs, le service worker. Reconstruire un [NavigationWebController]
  /// pour ça reviendrait à démonter la vue plateforme, donc à repayer un
  /// démarrage complet de la carte au bord de la route.
  ///
  /// L'enregistrement n'y touche pas : il vit au-dessus de la navigation et
  /// continue d'écrire pendant le chargement.
  void openTarget(NavigationTarget next) {
    _target = next;
    load();
  }

  Future<bool> canGoBack() => webView.canGoBack();

  Future<void> goBack() => webView.goBack();

  /// La page est-elle connectée au site ? `null` quand la sonde échoue.
  Future<bool?> probeSession() => probeSignedIn(webView);

  /// Communique à la page les zones matériellement obstruées de son cadre.
  ///
  /// En plein écran, la carte passe volontiers derrière l'encoche — mais pas
  /// le bandeau de virage, qui devient illisible sous la caméra. La page ne
  /// peut pas deviner ces mesures : `env(safe-area-inset-*)` reste à zéro dans
  /// un WebView tant que la fenêtre n'est pas déclarée en mode découpe. On les
  /// pousse donc en variables CSS, que les bandeaux du haut ajoutent à leur
  /// position ; dans un navigateur ordinaire elles n'existent pas et valent 0.
  Future<void> pushInsets(EdgeInsets insets) async {
    await webView.runJavaScript(
      "document.documentElement.style.setProperty('--app-inset-top', '${insets.top}px');"
      "document.documentElement.style.setProperty('--app-inset-bottom', '${insets.bottom}px');",
    );
  }

  /// Prévient la page qu'elle n'est plus regardée (une page de données est
  /// passée par-dessus). Elle en profite pour couper ses animations sans rien
  /// endormir : position, virages et arrivée continuent de tourner.
  ///
  /// `?.` sur l'objet ET sur la méthode : un site plus ancien n'expose pas
  /// `setOccluded`, et l'appeler ne doit pas lever d'exception.
  Future<void> setOccluded(bool hidden) async {
    try {
      await webView.runJavaScript(
        'void (window.sportsScopeCompanion?.setOccluded?.($hidden));',
      );
    } catch (e) {
      // Page en cours de rechargement : la prochaine occultation repartira.
      debugPrint('[web] occultation ignorée : $e');
    }
  }

  void _onPageMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      onMessage(decoded);
    } catch (_) {
      // Message hors protocole : on l'ignore, la navigation prime.
    }
  }

  void dispose() {
    bridge.dispose();
    progress.dispose();
    error.dispose();
  }
}

/// Le rendu du WebView : la page, sa barre de progression, son écran d'erreur.
/// Rien d'autre — tout l'état vit dans le [NavigationWebController].
class NavigationWebView extends StatelessWidget {
  const NavigationWebView({super.key, required this.controller});

  final NavigationWebController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: controller.error,
      builder: (context, error, _) {
        if (error != null) return SafeArea(child: _errorView(context, error));

        return Stack(
          children: [
            WebViewWidget(controller: controller.webView),
            ValueListenableBuilder<int>(
              valueListenable: controller.progress,
              builder: (context, progress, _) => progress < 100
                  ? LinearProgressIndicator(value: progress / 100)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _errorView(BuildContext context, String error) {
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
            Text(error, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
