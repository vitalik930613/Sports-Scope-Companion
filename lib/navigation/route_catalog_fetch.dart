import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'nav_session.dart';
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
  const RouteFetchResult(this.status, [this.routes = const [], this.session]);

  final RouteFetchStatus status;
  final List<RouteSummary> routes;

  /// Le tracé en cours dans le stockage de la page, s'il y en a un.
  ///
  /// **Indépendant de [status]** : il se lit dans le navigateur, pas sur le
  /// site. Une session expirée ou un site en panne n'empêchent pas de reprendre
  /// ce qu'on suivait il y a dix minutes.
  final NavSessionSummary? session;
}

/// Va chercher ce que le site sait de mes itinéraires — la liste du compte et
/// le tracé en cours — **par le pot de cookies du WebView**.
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
/// **La page chargée est `robots.txt`**, et ce n'est pas une coquetterie : on ne
/// veut qu'une *origine* d'où émettre. Charger la racine du site amènerait toute
/// l'application Vue, son service worker et ses dizaines de requêtes — long,
/// et surtout riche en occasions d'échouer pour des raisons qui n'ont rien à
/// voir avec ce qu'on demande. Un fichier texte statique n'a ni JavaScript, ni
/// sous-ressource, ni cycle de vie.
///
/// **Le tracé en cours voyage avec.** Il vit dans le `localStorage` du site, que
/// ce document partage puisqu'il en a l'origine ; le lire ici plutôt que dans un
/// second WebView épargne un chargement complet au moment précis où le cycliste
/// attend sa liste. Rien n'en est gardé sur disque : une entrée conservée après
/// que la page a fini sa navigation ferait proposer de reprendre un tracé qui
/// n'existe plus, et le tap retomberait sans un mot sur la carte nue. Pas de
/// réseau, pas de reprise — on choisit alors son itinéraire dans la liste, qui
/// est en cache, elle.
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

  /// Le document qui sert d'origine. Statique, minuscule, sans JavaScript.
  static const _originPath = '/robots.txt';

  /// Le `fetch` lui-même.
  ///
  /// - `same-origin` embarque le cookie de session ;
  /// - `Accept: application/json` est ce qui fait répondre à Rails un 401 propre
  ///   plutôt qu'une redirection HTML vers la page de connexion — c'est ce qui
  ///   permet de distinguer « pas connecté » de « pas de réseau » ;
  /// - `no-store` parce qu'une liste d'itinéraires servie depuis un cache HTTP
  ///   n'aurait aucun intérêt : on a déjà le nôtre, sur disque.
  ///
  /// Le code HTTP est renvoyé même en cas d'échec : c'est la seule chose qui
  /// permette de diagnostiquer depuis un téléphone au bout d'un `adb`.
  ///
  /// Le tracé en cours est lu **avant** le `fetch` et joint à *chaque* réponse,
  /// y compris aux échecs : il ne vient pas du réseau, il n'a aucune raison de
  /// tomber avec lui.
  ///
  /// De la session on n'extrait que le nom, le token et la date. Le reste — la
  /// géométrie surtout — pèse des mégaoctets qu'il faudrait sérialiser puis
  /// reparser pour afficher une ligne de liste, alors que c'est la page qui
  /// restaurera le tracé, pas nous.
  static const _script = '''
    (function () {
      var session = null;
      try {
        var raw = localStorage.getItem('${NavSessionSummary.storageKey}');
        var saved = raw ? JSON.parse(raw) : null;
        if (saved && saved.v === 1) {
          session = { name: saved.name, token: saved.token, t: saved.t };
        }
      } catch (e) {}

      var send = function (payload) {
        payload.session = session;
        try { $_channel.postMessage(JSON.stringify(payload)); } catch (e) {}
      };
      try {
        fetch('/api/routes', {
          credentials: 'same-origin',
          cache: 'no-store',
          headers: { 'Accept': 'application/json' }
        }).then(function (response) {
          if (response.status === 401) return send({ status: 'signedOut' });
          if (!response.ok) {
            return send({ status: 'failed', code: response.status });
          }
          return response.json().then(function (body) {
            send({ status: 'ok', body: body });
          });
        }).catch(function (e) {
          send({ status: 'failed', reason: String(e) });
        });
      } catch (e) {
        send({ status: 'failed', reason: String(e) });
      }
    })();
  ''';

  Future<RouteFetchResult> run() async {
    final answer = Completer<RouteFetchResult>();
    late final WebViewController controller;
    Timer? retries;

    void finish(RouteFetchResult result) {
      if (answer.isCompleted) return;
      retries?.cancel();
      answer.complete(result);
    }

    void ask() {
      controller.runJavaScript(_script).catchError((Object e) {
        debugPrint('[itinéraires] script refusé : $e');
      });
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
            onPageFinished: (url) {
              debugPrint('[itinéraires] origine chargée : $url');
              ask();
            },
            onWebResourceError: (error) {
              // **Seule une erreur de cadre principal est fatale.** Android
              // signale ici la moindre sous-ressource en échec — une icône
              // manquante, une requête coupée — et traiter ça comme une panne
              // faisait abandonner la requête avant même de l'avoir émise.
              if (error.isForMainFrame != true) {
                debugPrint('[itinéraires] ressource ignorée : '
                    '${error.url} (${error.description})');
                return;
              }
              debugPrint('[itinéraires] origine injoignable : '
                  '${error.description}');
              finish(const RouteFetchResult(RouteFetchStatus.failed));
            },
          ),
        );

      await controller.loadRequest(Uri.parse('$baseUrl$_originPath'));

      // Filet : `onPageFinished` peut ne jamais venir, ou venir avant que le
      // canal ne soit prêt. Redemander coûte un `fetch` de plus au pire, et
      // évite d'attendre le délai complet pour rien.
      retries = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => ask(),
      );
    } catch (e) {
      debugPrint('[itinéraires] rafraîchissement impossible : $e');
      retries?.cancel();
      return const RouteFetchResult(RouteFetchStatus.failed);
    }

    final result = await answer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[itinéraires] pas de réponse en ${timeout.inSeconds} s');
        retries?.cancel();
        return const RouteFetchResult(RouteFetchStatus.failed);
      },
    );

    retries.cancel();
    debugPrint('[itinéraires] ${result.status.name}, '
        '${result.routes.length} itinéraire(s), '
        'en cours : ${result.session ?? "aucun"}');
    return result;
  }

  RouteFetchResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return const RouteFetchResult(RouteFetchStatus.failed);
      }

      final session = NavSessionSummary.parse(decoded['session']);

      return switch (decoded['status']) {
        'ok' => RouteFetchResult(
            RouteFetchStatus.ok,
            RouteSummary.listFromPayload(decoded['body']),
            session,
          ),
        'signedOut' =>
          RouteFetchResult(RouteFetchStatus.signedOut, const [], session),
        _ => _failure(decoded, session),
      };
    } catch (e) {
      debugPrint('[itinéraires] réponse illisible : $e');
      return const RouteFetchResult(RouteFetchStatus.failed);
    }
  }

  RouteFetchResult _failure(
    Map<dynamic, dynamic> decoded,
    NavSessionSummary? session,
  ) {
    debugPrint('[itinéraires] échec du fetch : '
        'code=${decoded['code']} raison=${decoded['reason']}');
    return RouteFetchResult(RouteFetchStatus.failed, const [], session);
  }
}
