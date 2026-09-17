import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation/navigation_target.dart';

enum MapStyleWriteStatus { ok, signedOut, failed }

@immutable
class MapStyleWriteResult {
  const MapStyleWriteResult(this.status, {this.id});

  final MapStyleWriteStatus status;

  /// Le fond réellement retenu par le serveur, sur succès — la liste blanche
  /// peut différer de ce qui a été demandé si l'id était invalide. `null`
  /// sinon.
  final String? id;
}

/// `PATCH /api/companion_settings/map_style` depuis l'appli — le fond de carte
/// de la navigation guidée, choisi hors d'une sortie (voir
/// `CompanionSettingsPage`) puisque `NavControlsPanel`, qui le propose en
/// navigateur, est masqué dans l'appli (`appOwnsChrome`, dépôt Rails).
///
/// Même patron que [CompanionSettingsWrite] (`companion_settings_write.dart`),
/// dupliqué à dessein plutôt que factorisé — voir son commentaire : origine
/// authentifiée `/companion` pour porter le jeton CSRF (`/robots.txt`, statique,
/// n'en a pas), un seul envoi par appel, un PATCH n'étant pas rejouable sans
/// risque comme un GET.
///
/// Contrairement à `CompanionSettingsWrite`, le corps n'est **pas** le document
/// entier : cet endpoint fusionne côté serveur
/// (`ProfilesController#update_navigation_style`), donc un seul champ suffit —
/// et surtout, contrairement à `PATCH /api/profile/preferences` (qui attend
/// l'objet complet et assainit le reste), il ne risque pas d'écraser en silence
/// les autres préférences du compte avec leurs valeurs d'usine.
class MapStyleWrite {
  const MapStyleWrite({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 20),
  });

  final String baseUrl;
  final Duration timeout;

  static const _channel = 'SportsScopeMapStyleWrite';
  // Une page authentifiée du site (donc porteuse du jeton CSRF) : `/companion`
  // n'a d'autre rôle que d'exister pour ce chargement hors écran.
  static const _originPath = '/companion';

  Future<MapStyleWriteResult> run(String id) async {
    final answer = Completer<MapStyleWriteResult>();
    late final WebViewController controller;
    Timer? retries;
    var asked = false;

    void finish(MapStyleWriteResult result) {
      if (answer.isCompleted) return;
      retries?.cancel();
      answer.complete(result);
    }

    void ask() {
      // Un seul envoi : redemander à chaque tick du minuteur de secours
      // enverrait la même écriture en rafale si la première réponse tarde.
      if (asked) return;
      asked = true;
      controller.runJavaScript(_scriptFor(id)).catchError((Object e) {
        debugPrint('[fond de carte] script refusé : $e');
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
              debugPrint('[fond de carte] origine chargée : $url');
              ask();
            },
            onWebResourceError: (error) {
              // Seule une erreur de cadre principal est fatale — même garde
              // que CompanionSettingsWrite/RouteCatalogFetch.
              if (error.isForMainFrame != true) {
                debugPrint('[fond de carte] ressource ignorée : '
                    '${error.url} (${error.description})');
                return;
              }
              debugPrint('[fond de carte] origine injoignable : '
                  '${error.description}');
              finish(const MapStyleWriteResult(MapStyleWriteStatus.failed));
            },
          ),
        );

      await controller.loadRequest(Uri.parse('$baseUrl$_originPath'));

      retries = Timer(const Duration(seconds: 4), ask);
    } catch (e) {
      debugPrint('[fond de carte] impossible : $e');
      retries?.cancel();
      return const MapStyleWriteResult(MapStyleWriteStatus.failed);
    }

    final result = await answer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[fond de carte] pas de réponse en ${timeout.inSeconds} s');
        retries?.cancel();
        return const MapStyleWriteResult(MapStyleWriteStatus.failed);
      },
    );

    retries.cancel();
    debugPrint('[fond de carte] ${result.status.name}');
    return result;
  }

  String _scriptFor(String id) => '''
    (function () {
      var send = function (result) {
        try { $_channel.postMessage(JSON.stringify(result)); } catch (e) {}
      };
      try {
        var meta = document.querySelector('meta[name="csrf-token"]');
        var csrf = meta ? meta.getAttribute('content') : '';
        fetch('/api/companion_settings/map_style', {
          method: 'PATCH',
          credentials: 'same-origin',
          cache: 'no-store',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': csrf || ''
          },
          body: JSON.stringify({ id: ${jsonEncode(id)} })
        }).then(function (response) {
          if (response.status === 401) return send({ status: 'signedOut' });
          if (response.ok) {
            return response.json().then(function (json) {
              send({ status: 'ok', id: json.default_style });
            });
          }
          return response.text().then(function (text) {
            send({ status: 'failed', code: response.status, body: text });
          });
        }).catch(function (e) {
          send({ status: 'failed', reason: String(e) });
        });
      } catch (e) {
        send({ status: 'failed', reason: String(e) });
      }
    })();
  ''';

  MapStyleWriteResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return const MapStyleWriteResult(MapStyleWriteStatus.failed);
      }

      return switch (decoded['status']) {
        'ok' => MapStyleWriteResult(
            MapStyleWriteStatus.ok,
            id: decoded['id'] is String ? decoded['id'] as String : null,
          ),
        'signedOut' => const MapStyleWriteResult(MapStyleWriteStatus.signedOut),
        _ => const MapStyleWriteResult(MapStyleWriteStatus.failed),
      };
    } catch (e) {
      debugPrint('[fond de carte] réponse illisible : $e');
      return const MapStyleWriteResult(MapStyleWriteStatus.failed);
    }
  }
}
