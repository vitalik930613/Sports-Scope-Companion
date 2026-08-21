import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../navigation/navigation_target.dart';
import 'training_program.dart';

/// Va chercher un programme d'entraînement par son jeton de partage —
/// `?workout=<token>` sur le lien de navigation (voir [NavigationTarget]).
///
/// **HTTP direct, pas le passage par WebView** de `RouteCatalogFetch` :
/// `GET /api/training_programs/shared/:token` est **public** côté Rails
/// (comme `/api/companion_version`, cf. `UpdateChecker`), l'appli n'a donc
/// aucun cookie à faire valoir pour le lire. Le résoudre par WebView pour un
/// seul programme, au moment précis où le cycliste attend que sa sortie
/// s'ouvre, coûterait un chargement complet pour rien.
Future<TrainingProgram?> fetchSharedTrainingProgram(
  String shareToken, {
  String baseUrl = sportsScopeBaseUrl,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final url = Uri.parse('$baseUrl/api/training_programs/shared/$shareToken');
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final body = await response.transform(const Utf8Decoder()).join();
    return TrainingProgram.parse(jsonDecode(body));
  } catch (e) {
    // Muet comme `UpdateChecker` : un programme introuvable ne doit pas
    // empêcher la sortie de s'ouvrir, elle part alors sans lui.
    debugPrint('[entraînement] programme injoignable : $e');
    return null;
  } finally {
    client.close(force: true);
  }
}
