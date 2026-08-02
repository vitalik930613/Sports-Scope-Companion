import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../navigation/navigation_target.dart';
import 'companion_release.dart';

/// Va demander au site s'il publie une version plus récente que celle qui
/// tourne.
///
/// L'appli est diffusée hors Play Store : rien ne la met à jour toute seule, et
/// sans ce contrôle les téléphones divergent en silence — jusqu'au jour où le
/// protocole du pont ne correspond plus entre les deux dépôts, ce qui se
/// manifeste par une navigation aux capteurs muets et aucune explication.
///
/// L'endpoint est **public** côté Rails, exprès : l'appli ne détient aucun
/// cookie côté Dart (la session vit dans le pot partagé des WebViews), et le
/// faire passer par le WebView hors écran de `RouteCatalogFetch` pour lire un
/// numéro de version serait beaucoup de machinerie. Effet de bord utile : le
/// contrôle marche encore quand la session a expiré.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    this.baseUrl = sportsScopeBaseUrl,
    Future<String?> Function(Uri)? fetch,
    Future<int> Function()? installedCode,
  })  : _fetch = fetch ?? _fetchOverHttp,
        _installedCode = installedCode ?? _installedCodeFromPlatform;

  final String baseUrl;
  final Future<String?> Function(Uri) _fetch;
  final Future<int> Function() _installedCode;

  /// La version à proposer, `null` quand il n'y a rien à dire — pas encore
  /// interrogé, hors ligne, ou déjà à jour. Un seul état pour ces quatre cas :
  /// l'écran n'a qu'une carte à afficher ou non, et « le contrôle a échoué »
  /// n'est pas une information qu'on veut poser sur l'écran d'avant-départ.
  CompanionRelease? get available => _available;
  CompanionRelease? _available;

  /// Interroge le site. **Ne lève jamais et n'attend pas longtemps** : c'est
  /// appelé au lancement, et être hors ligne avant de partir est banal.
  Future<void> check() async {
    try {
      final body = await _fetch(Uri.parse('$baseUrl/api/companion_version'));
      if (body == null) return;

      final release = CompanionRelease.parse(body);
      if (release == null) return;

      final installed = await _installedCode();
      final next = release.isNewerThan(installed) ? release : null;
      if (next?.versionCode == _available?.versionCode) return;

      _available = next;
      notifyListeners();
    } catch (e) {
      // Volontairement muet côté écran : un échec de contrôle de version n'est
      // pas un problème du cycliste.
      debugPrint('[maj] contrôle impossible : $e');
    }
  }

  static Future<String?> _fetchOverHttp(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      // 404 est la réponse normale tant que rien n'est publié : ce n'est pas une
      // panne, il n'y a simplement rien à proposer.
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return await response.transform(const Utf8Decoder()).join();
    } finally {
      client.close(force: true);
    }
  }

  static Future<int> _installedCodeFromPlatform() async {
    final info = await PackageInfo.fromPlatform();
    // `buildNumber` est le versionCode Android, en texte. Un vide (build sans
    // `+N` dans le pubspec) donne 0, donc « tout est plus récent » — c'est le
    // bon défaut : mieux vaut proposer une mise à jour de trop que jamais.
    return int.tryParse(info.buildNumber) ?? 0;
  }
}
