import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'navigation_target.dart';

/// Échange un [NavigationTarget.handoffToken] contre le cookie de session
/// Rails, **avant** d'ouvrir la sortie.
///
/// Sans ça, un lien « Naviguer dans l'application » sur un téléphone qui n'a
/// jamais eu de session dans l'appli (install fraîche, ou premier lien de ce
/// lancement) ouvre `RideShellPage` avant que quoi que ce soit ne soit
/// authentifié : `settings.select(target.presetKey)` retombe alors sur le
/// profil de repli, et la sortie tout entière tourne dessus — le jeton ne
/// s'échange normalement que plus tard, dans le WebView de navigation lui-même.
/// En le consommant ici d'abord, `_openLink` peut rafraîchir les profils avec
/// une session déjà valide et choisir le bon **avant** que la carte n'ouvre.
///
/// **Le jeton ne vaut qu'une fois.** Un échange réussi ici doit donc retirer
/// `handoffToken` du [NavigationTarget] (voir `withoutHandoffToken`) avant de
/// l'ouvrir : le WebView de navigation, qui ferait sinon le même échange une
/// seconde fois, le trouverait déjà consommé et retomberait en anonyme —
/// par-dessus la session qu'on vient tout juste d'ouvrir.
///
/// Même patron que [CompanionSettingsFetch]/[RouteCatalogFetch] : un WebView
/// hors écran, jeté après usage. La destination importe peu — seul compte le
/// `Set-Cookie` de la réponse `/auth/handoff` — donc `/robots.txt`, statique et
/// sans JavaScript, comme les deux autres.
class HandoffExchange {
  const HandoffExchange({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 12),
  });

  final String baseUrl;

  /// Au-delà, on renonce : la sortie doit s'ouvrir, avec ou sans le bon
  /// profil, plutôt que de laisser le cycliste devant un écran qui charge.
  final Duration timeout;

  static const _landingPath = '/robots.txt';

  /// Rend `true` si le cookie a pu être posé. `false` — jeton expiré ou déjà
  /// utilisé, site injoignable, réponse inattendue — laisse l'appelant ouvrir
  /// la sortie sans y avoir touché : le jeton original reste sur la cible, et
  /// le WebView de navigation tentera l'échange lui-même, exactement comme
  /// avant ce chantier.
  Future<bool> run(String token) async {
    final completer = Completer<bool>();
    late final WebViewController controller;

    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              debugPrint('[handoff] session posée : $url');
              finish(true);
            },
            onWebResourceError: (error) {
              // Même garde que les autres fetches hors écran : seule une
              // erreur de cadre principal est fatale, le reste est du bruit
              // de sous-ressource sans rapport avec le `Set-Cookie` qu'on
              // attend.
              if (error.isForMainFrame != true) return;
              debugPrint('[handoff] échange impossible : ${error.description}');
              finish(false);
            },
          ),
        );

      final uri = Uri.parse(baseUrl).replace(
        path: '/auth/handoff',
        queryParameters: {'token': token, 'next': _landingPath},
      );
      await controller.loadRequest(uri);
    } catch (e) {
      debugPrint('[handoff] rafraîchissement impossible : $e');
      return false;
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[handoff] pas de réponse en ${timeout.inSeconds} s');
        return false;
      },
    );
  }
}
