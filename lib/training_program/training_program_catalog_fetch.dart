import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../navigation/navigation_target.dart';
import 'training_program_summary.dart';

/// Comment s'est terminé un rafraîchissement du catalogue — mêmes trois issues
/// que `RouteFetchStatus`, pour la même raison.
enum TrainingProgramFetchStatus { ok, signedOut, failed }

@immutable
class TrainingProgramFetchResult {
  const TrainingProgramFetchResult(this.status, [this.programs = const []]);

  final TrainingProgramFetchStatus status;
  final List<TrainingProgramSummary> programs;
}

/// Va chercher les programmes d'entraînement du compte — même mécanisme que
/// `RouteCatalogFetch` : un WebView invisible chargé sur `/robots.txt` pour
/// n'être qu'une origine d'où émettre un `fetch('/api/training_programs')`
/// **par le pot de cookies du WebView**, l'appli n'ayant elle-même aucun
/// identifiant. Voir la documentation de `RouteCatalogFetch` pour le détail
/// de ce choix — il s'applique ici à l'identique.
class TrainingProgramCatalogFetch {
  const TrainingProgramCatalogFetch({
    this.baseUrl = sportsScopeBaseUrl,
    this.timeout = const Duration(seconds: 12),
  });

  final String baseUrl;
  final Duration timeout;

  static const _channel = 'SportsScopeTrainingPrograms';
  static const _originPath = '/robots.txt';

  static const _script = '''
    (function () {
      var send = function (payload) {
        try { $_channel.postMessage(JSON.stringify(payload)); } catch (e) {}
      };
      try {
        fetch('/api/training_programs', {
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

  Future<TrainingProgramFetchResult> run() async {
    final answer = Completer<TrainingProgramFetchResult>();
    late final WebViewController controller;
    Timer? retries;

    void finish(TrainingProgramFetchResult result) {
      if (answer.isCompleted) return;
      retries?.cancel();
      answer.complete(result);
    }

    void ask() {
      controller.runJavaScript(_script).catchError((Object e) {
        debugPrint('[entraînement] script refusé : $e');
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
              if (error.isForMainFrame != true) return;
              debugPrint('[entraînement] origine injoignable : '
                  '${error.description}');
              finish(const TrainingProgramFetchResult(
                  TrainingProgramFetchStatus.failed));
            },
          ),
        );

      await controller.loadRequest(Uri.parse('$baseUrl$_originPath'));

      retries = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => ask(),
      );
    } catch (e) {
      debugPrint('[entraînement] rafraîchissement impossible : $e');
      retries?.cancel();
      return const TrainingProgramFetchResult(TrainingProgramFetchStatus.failed);
    }

    final result = await answer.future.timeout(
      timeout,
      onTimeout: () {
        retries?.cancel();
        return const TrainingProgramFetchResult(TrainingProgramFetchStatus.failed);
      },
    );

    retries.cancel();
    return result;
  }

  TrainingProgramFetchResult _decode(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return const TrainingProgramFetchResult(TrainingProgramFetchStatus.failed);
      }
      return switch (decoded['status']) {
        'ok' => TrainingProgramFetchResult(
            TrainingProgramFetchStatus.ok,
            TrainingProgramSummary.listFromPayload(decoded['body']),
          ),
        'signedOut' =>
          const TrainingProgramFetchResult(TrainingProgramFetchStatus.signedOut),
        _ => const TrainingProgramFetchResult(TrainingProgramFetchStatus.failed),
      };
    } catch (e) {
      debugPrint('[entraînement] réponse illisible : $e');
      return const TrainingProgramFetchResult(TrainingProgramFetchStatus.failed);
    }
  }
}
