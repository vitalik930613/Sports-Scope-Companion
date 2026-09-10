import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation/navigation_target.dart';

enum CompanionSettingsWriteStatus { ok, signedOut, failed }

@immutable
class CompanionSettingsWriteResult {
  const CompanionSettingsWriteResult(this.status, {this.document, this.message});

  final CompanionSettingsWriteStatus status;

  /// Le document **assaini par le serveur**, sur succès — c'est lui qu'il faut
  /// remettre dans `CompanionSettingsStore` (via `record`), jamais le document
  /// envoyé : même contrat que l'éditeur web (« ce qu'on voit après enregistrer
  /// est exactement ce que l'appli recevra »).
  final Object? document;
  final String? message;
}

/// `PATCH /api/companion_settings` depuis l'appli elle-même — jusqu'ici seul
/// l'éditeur web (`CompanionDashboard`) écrivait ce document. Même principe que
/// `RideUploadFetch` (dépôt `lib/recording/`) : l'appli n'a pas de cookie propre,
/// la session vit dans le pot partagé des WebViews, donc l'écriture passe par un
/// WebView hors écran chargé sur une page authentifiée — porteuse du jeton CSRF,
/// contrairement à un fichier statique comme `/robots.txt` (suffisant pour la
/// simple lecture de `CompanionSettingsFetch`).
///
/// **Le corps envoyé doit être le document COMPLET**, jamais `{"col_detection":
/// ...}` seul : `CompanionSettings.sanitize` (dépôt Rails) remplace tout le
/// document par les préréglages d'usine si `presets` est absent ou vide — voir
/// `CompanionSettingsStore.rawDocument`, seule source à utiliser pour construire
/// ce corps.
///
/// Pas de classe de base partagée avec `CompanionSettingsFetch`/
/// `RouteCatalogFetch` : ce projet duplique volontairement l'échafaudage
/// WebView/minuteur de secours/timeout de chaque helper plutôt que d'en factoriser
/// un (lecture vs écriture, origines et jetons différents).
class CompanionSettingsWrite {
  const CompanionSettingsWrite({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 20),
  });

  final String baseUrl;
  final Duration timeout;

  static const _channel = 'SportsScopeSettingsWrite';
  // Une page authentifiée du site (donc porteuse du jeton CSRF) : `/companion`
  // n'a d'autre rôle que d'exister pour ce chargement hors écran.
  static const _originPath = '/companion';

  Future<CompanionSettingsWriteResult> run(Map<String, dynamic> document) async {
    final answer = Completer<CompanionSettingsWriteResult>();
    late final WebViewController controller;
    Timer? retries;
    var asked = false;

    void finish(CompanionSettingsWriteResult result) {
      if (answer.isCompleted) return;
      retries?.cancel();
      answer.complete(result);
    }

    void ask() {
      // Un seul envoi : un PATCH n'est pas rejouable sans risque comme un GET,
      // le redemander à chaque tick du minuteur de secours enverrait la même
      // écriture en rafale si la première réponse tarde.
      if (asked) return;
      asked = true;
      controller.runJavaScript(_scriptFor(document)).catchError((Object e) {
        debugPrint('[réglages companion] script refusé : $e');
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
              debugPrint('[réglages companion] origine chargée : $url');
              ask();
            },
            onWebResourceError: (error) {
              // Seule une erreur de cadre principal est fatale — même garde que
              // RouteCatalogFetch/RideUploadFetch.
              if (error.isForMainFrame != true) {
                debugPrint('[réglages companion] ressource ignorée : '
                    '${error.url} (${error.description})');
                return;
              }
              debugPrint('[réglages companion] origine injoignable : '
                  '${error.description}');
              finish(const CompanionSettingsWriteResult(CompanionSettingsWriteStatus.failed));
            },
          ),
        );

      await controller.loadRequest(Uri.parse('$baseUrl$_originPath'));

      retries = Timer(const Duration(seconds: 4), ask);
    } catch (e) {
      debugPrint('[réglages companion] impossible : $e');
      retries?.cancel();
      return const CompanionSettingsWriteResult(CompanionSettingsWriteStatus.failed);
    }

    final result = await answer.future.timeout(
      timeout,
      onTimeout: () {
        debugPrint('[réglages companion] pas de réponse en ${timeout.inSeconds} s');
        retries?.cancel();
        return const CompanionSettingsWriteResult(CompanionSettingsWriteStatus.failed);
      },
    );

    retries.cancel();
    debugPrint('[réglages companion] ${result.status.name}');
    return result;
  }

  String _scriptFor(Map<String, dynamic> document) => '''
    (function () {
      var body = ${jsonEncode(document)};
      var send = function (result) {
        try { $_channel.postMessage(JSON.stringify(result)); } catch (e) {}
      };
      try {
        var meta = document.querySelector('meta[name="csrf-token"]');
        var csrf = meta ? meta.getAttribute('content') : '';
        fetch('/api/companion_settings', {
          method: 'PATCH',
          credentials: 'same-origin',
          cache: 'no-store',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': csrf || ''
          },
          body: JSON.stringify(body)
        }).then(function (response) {
          if (response.status === 401) return send({ status: 'signedOut' });
          if (response.ok) {
            return response.json().then(function (json) {
              send({ status: 'ok', document: json });
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

  CompanionSettingsWriteResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return const CompanionSettingsWriteResult(CompanionSettingsWriteStatus.failed);
      }

      return switch (decoded['status']) {
        'ok' => CompanionSettingsWriteResult(
            CompanionSettingsWriteStatus.ok,
            document: decoded['document'],
          ),
        'signedOut' => const CompanionSettingsWriteResult(CompanionSettingsWriteStatus.signedOut),
        _ => CompanionSettingsWriteResult(
            CompanionSettingsWriteStatus.failed,
            message: decoded['reason']?.toString() ??
                (decoded['code'] != null ? 'HTTP ${decoded['code']}' : null),
          ),
      };
    } catch (e) {
      debugPrint('[réglages companion] réponse illisible : $e');
      return const CompanionSettingsWriteResult(CompanionSettingsWriteStatus.failed);
    }
  }
}
