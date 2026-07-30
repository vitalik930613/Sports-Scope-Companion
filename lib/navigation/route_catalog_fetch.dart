import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'navigation_target.dart';
import 'route_summary.dart';

/// Comment s'est terminé un rafraîchissement du catalogue.
enum RouteFetchStatus {
  ok,

  /// Le site a répondu 401 : personne n'est connecté dans le pot de cookies.
  /// À dire tel quel — c'est le seul échec que le cycliste puisse corriger.
  signedOut,

  /// Réseau absent, site injoignable, réponse incompréhensible. Indiscernables
  /// de l'appli, et de toute façon rien à en faire d'autre que de garder le
  /// cache.
  failed,
}

@immutable
class RouteFetchResult {
  const RouteFetchResult(this.status, [this.routes = const []]);

  final RouteFetchStatus status;
  final List<RouteSummary> routes;
}

/// Va chercher les itinéraires du compte, **par le pot de cookies du WebView**.
///
/// L'appli ne détient aucun identifiant, par construction : la session est le
/// cookie posé par une vraie connexion Keycloak dans un WebView. Un client HTTP
/// natif devrait donc extraire ce cookie du pot d'Android pour le rejouer — deux
/// fragilités (une dépendance de plus, et une API de lecture de cookies que
/// `webview_flutter` n'expose même pas).
///
/// À la place, c'est un WebView qui appelle : invisible, jamais attaché à
/// l'arbre de widgets, chargé le temps d'un `fetch` puis jeté. Tous les WebViews
/// d'une même appli Android partagent un seul pot, donc celui-ci est connecté
/// exactement comme l'écran Compte l'a laissé. Aucune dépendance nouvelle,
/// aucune session à recopier, et rien à changer côté Rails.
///
/// Le prix, c'est un chargement de page du site pour pouvoir émettre depuis la
/// bonne origine. C'est aussi la raison pour laquelle le résultat est mis en
/// cache : on ne paie ça qu'une fois par départ, et jamais hors ligne.
class RouteCatalogFetch {
  const RouteCatalogFetch({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 12),
  });

  final String baseUrl;

  /// Au-delà, on rend la main avec ce qu'on a. Un cycliste gants aux mains ne
  /// regarde pas une roue qui tourne : le cache est déjà à l'écran, et un
  /// rafraîchissement qui traîne ne vaut pas de le faire attendre.
  final Duration timeout;

  static const _channel = 'SportsScopeRoutes';

  /// Le `fetch` lui-même. `same-origin` embarque le cookie de session, et
  /// `Accept: application/json` est ce qui fait répondre à Rails un 401 propre
  /// plutôt qu'une redirection HTML vers la page de connexion — c'est ce qui
  /// nous permet de distinguer « pas connecté » de « pas de réseau ».
  static const _script = '''
    (function () {
      var send = function (payload) {
        try { $_channel.postMessage(JSON.stringify(payload)); } catch (e) {}
      };
      fetch('/api/routes', {
        credentials: 'same-origin',
        headers: { 'Accept': 'application/json' }
      }).then(function (response) {
        if (response.status === 401) return send({ status: 'signedOut' });
        if (!response.ok) return send({ status: 'failed' });
        return response.json().then(function (body) {
          send({ status: 'ok', body: body });
        });
      }).catch(function () { send({ status: 'failed' }); });
    })();
  ''';

  Future<RouteFetchResult> run() async {
    final answer = Completer<RouteFetchResult>();
    late final WebViewController controller;

    void finish(RouteFetchResult result) {
      if (!answer.isCompleted) answer.complete(result);
    }

    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          _channel,
          onMessageReceived: (message) => finish(_decode(message.message)),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            // La page n'est là que pour donner une origine au `fetch` : ce
            // qu'elle affiche n'a aucune importance, personne ne la regarde.
            onPageFinished: (_) => controller.runJavaScript(_script),
            onWebResourceError: (_) => finish(
              const RouteFetchResult(RouteFetchStatus.failed),
            ),
          ),
        );

      await controller.loadRequest(Uri.parse(baseUrl));
    } catch (e) {
      debugPrint('[itinéraires] rafraîchissement impossible : $e');
      return const RouteFetchResult(RouteFetchStatus.failed);
    }

    return answer.future.timeout(
      timeout,
      onTimeout: () => const RouteFetchResult(RouteFetchStatus.failed),
    );
  }

  RouteFetchResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return const RouteFetchResult(RouteFetchStatus.failed);
      }

      return switch (decoded['status']) {
        'ok' => RouteFetchResult(
            RouteFetchStatus.ok,
            RouteSummary.listFromPayload(decoded['body']),
          ),
        'signedOut' => const RouteFetchResult(RouteFetchStatus.signedOut),
        _ => const RouteFetchResult(RouteFetchStatus.failed),
      };
    } catch (e) {
      debugPrint('[itinéraires] réponse illisible : $e');
      return const RouteFetchResult(RouteFetchStatus.failed);
    }
  }
}
