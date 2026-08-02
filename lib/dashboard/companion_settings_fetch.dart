import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation/navigation_target.dart';
import 'companion_settings_store.dart';

/// Va chercher les profils et les range, en un geste.
///
/// Les deux appelants n'ont rien d'autre à en faire — le lancement de l'appli et
/// le retour d'une connexion réussie — et écrire deux fois « si ok, enregistre »
/// finirait par donner deux politiques différentes du même échec.
///
/// **Un échec ne touche pas au cache** : hors ligne avant de partir est le cas
/// banal, et un site plus ancien que l'appli répond 404 sans que ce soit une
/// panne. Le magasin refuse de son côté un document vide de profils.
Future<void> refreshCompanionSettings(
  CompanionSettingsStore store, {
  CompanionSettingsFetch fetch = const CompanionSettingsFetch(),
}) async {
  final result = await fetch.run();
  if (result.status != SettingsFetchStatus.ok) return;
  await store.record(result.document);
}

/// Comment s'est terminé un rafraîchissement des profils.
enum SettingsFetchStatus {
  ok,

  /// Le site a répondu 401 : personne n'est connecté dans le pot de cookies.
  signedOut,

  /// Réseau absent, site injoignable, endpoint inexistant (un site plus ancien
  /// que l'appli), réponse incompréhensible. Indiscernables d'ici, et de toute
  /// façon rien à en faire d'autre que de garder le cache.
  failed,
}

@immutable
class SettingsFetchResult {
  const SettingsFetchResult(this.status, [this.document]);

  final SettingsFetchStatus status;

  /// Le document brut, tel que le site l'a servi. Non décodé ici : c'est le
  /// magasin qui le garde tel quel, et [CompanionSettings] qui l'interprète.
  final Object? document;
}

/// Va chercher les profils de sortie **par le pot de cookies du WebView**.
///
/// Même mécanique que [RouteCatalogFetch], et pour la même raison : l'appli ne
/// détient aucun identifiant, la session est le cookie posé par une vraie
/// connexion Keycloak dans un WebView. On fait donc appeler un WebView plutôt
/// que d'extraire le cookie du pot d'Android — que `webview_flutter` n'expose
/// même pas.
///
/// Le document est chargé **une fois par lancement**, et pas à chaque ouverture
/// de la feuille de départ comme le catalogue d'itinéraires : ces réglages
/// changent au plus une fois par mois, alors que les itinéraires changent la
/// veille d'une sortie. Un WebView hors écran par ouverture de feuille coûterait
/// une seconde d'attente pour un document identique.
///
/// L'endpoint est **authentifié**, contrairement à `/api/companion_version` : ce
/// sont des données de compte. C'est aussi pourquoi il passe par ici et pas par
/// un client HTTP natif.
class CompanionSettingsFetch {
  const CompanionSettingsFetch({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 12),
  });

  final String baseUrl;

  /// Au-delà, on rend la main : le cache est déjà à l'écran, et un
  /// rafraîchissement qui traîne ne vaut pas de faire attendre l'accueil.
  final Duration timeout;

  static const _channel = 'SportsScopeSettings';

  /// Le document qui sert d'origine. Statique, minuscule, sans JavaScript :
  /// charger la racine du site amènerait toute l'application Vue et ses dizaines
  /// d'occasions d'échouer pour des raisons sans rapport avec ce qu'on demande.
  static const _originPath = '/robots.txt';

  /// `Accept: application/json` est indispensable : c'est ce qui fait répondre à
  /// Rails un 401 propre au lieu d'une redirection HTML vers la page de
  /// connexion — donc ce qui permet de distinguer « pas connecté » de « pas de
  /// réseau ».
  ///
  /// Un **404 compte comme un échec ordinaire**, et c'est voulu : il veut dire
  /// que le site est plus ancien que l'appli et n'a pas encore cet endpoint. Le
  /// cycliste n'a rien à corriger, l'appli garde son tableau de bord intégré, et
  /// personne n'a besoin d'être prévenu.
  static const _script = '''
    (function () {
      var send = function (payload) {
        try { $_channel.postMessage(JSON.stringify(payload)); } catch (e) {}
      };
      try {
        fetch('/api/companion_settings', {
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

  Future<SettingsFetchResult> run() async {
    final answer = Completer<SettingsFetchResult>();
    late final WebViewController controller;
    Timer? retries;

    void finish(SettingsFetchResult result) {
      if (answer.isCompleted) return;
      retries?.cancel();
      answer.complete(result);
    }

    void ask() {
      controller.runJavaScript(_script).catchError((Object e) {
        debugPrint('[profils] script refusé : $e');
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
            onPageFinished: (url) => ask(),
            onWebResourceError: (error) {
              // **Seule une erreur de cadre principal est fatale.** Android
              // signale ici la moindre sous-ressource en échec, et traiter ça
              // comme une panne ferait abandonner la requête avant de l'émettre.
              if (error.isForMainFrame != true) return;
              debugPrint('[profils] origine injoignable : ${error.description}');
              finish(const SettingsFetchResult(SettingsFetchStatus.failed));
            },
          ),
        );

      await controller.loadRequest(Uri.parse('$baseUrl$_originPath'));

      // Filet : `onPageFinished` peut ne jamais venir, ou venir avant que le
      // canal ne soit prêt. Redemander coûte un `fetch` de plus au pire.
      retries = Timer.periodic(const Duration(milliseconds: 1500), (_) => ask());
    } catch (e) {
      debugPrint('[profils] rafraîchissement impossible : $e');
      retries?.cancel();
      return const SettingsFetchResult(SettingsFetchStatus.failed);
    }

    final result = await answer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[profils] pas de réponse en ${timeout.inSeconds} s');
        retries?.cancel();
        return const SettingsFetchResult(SettingsFetchStatus.failed);
      },
    );

    retries.cancel();
    debugPrint('[profils] ${result.status.name}');
    return result;
  }

  SettingsFetchResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return const SettingsFetchResult(SettingsFetchStatus.failed);
      }

      return switch (decoded['status']) {
        'ok' => SettingsFetchResult(SettingsFetchStatus.ok, decoded['body']),
        'signedOut' =>
          const SettingsFetchResult(SettingsFetchStatus.signedOut),
        _ => _failure(decoded),
      };
    } catch (e) {
      debugPrint('[profils] réponse illisible : $e');
      return const SettingsFetchResult(SettingsFetchStatus.failed);
    }
  }

  SettingsFetchResult _failure(Map<dynamic, dynamic> decoded) {
    debugPrint('[profils] échec du fetch : '
        'code=${decoded['code']} raison=${decoded['reason']}');
    return const SettingsFetchResult(SettingsFetchStatus.failed);
  }
}
