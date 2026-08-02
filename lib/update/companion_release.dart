import 'dart:convert';

import 'package:flutter/foundation.dart';

/// La version publiée sur le site, telle qu'annoncée par `/api/companion_version`.
///
/// Classe pure et testable : tout ce qui décide d'afficher ou non la carte de
/// mise à jour vit ici, l'écran ne fait que dessiner le résultat. C'est la même
/// répartition que `AutoReturnPolicy` ou `RadarWakePolicy` — la décision se teste
/// sans widget ni réseau.
@immutable
class CompanionRelease {
  const CompanionRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    this.size,
  });

  /// Ce qui s'affiche (« 0.2.0 »). Cosmétique : ne jamais s'en servir pour
  /// comparer deux versions, voir [isNewerThan].
  final String versionName;

  /// Le numéro qu'Android compare, et le seul qui ordonne les versions.
  final int versionCode;

  /// La page de téléchargement du site, pas le fichier : elle demande une
  /// session, et y arriver directement sur un `send_file` non authentifié
  /// donnerait une redirection silencieuse vers l'accueil.
  final String downloadUrl;

  /// Octets, `null` si le site ne l'a pas dit. Affiché avant le téléchargement :
  /// 19 Mo en 4G au bord de la route n'est pas la même décision qu'à la maison.
  final int? size;

  /// Décode la réponse du site. **Ne lève jamais** — même convention que les
  /// décodeurs GATT (`CharacteristicDecoder`) : le site peut être plus ancien
  /// que l'appli, répondre une page d'erreur HTML, ou un JSON amputé. Rien de
  /// tout ça ne doit remonter en exception dans un `initState`.
  static CompanionRelease? parse(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;

      final code = data['version_code'];
      final url = data['download_url'];
      // Sans ces deux-là il n'y a rien à proposer ni où l'envoyer : une carte
      // « mise à jour disponible » dont le tap ne mène nulle part est pire que
      // pas de carte du tout.
      if (code is! int || code <= 0) return null;
      if (url is! String || url.isEmpty) return null;

      final size = data['size'];
      return CompanionRelease(
        versionName: data['version_name'] is String
            ? data['version_name'] as String
            : '$code',
        versionCode: code,
        downloadUrl: url,
        size: size is int && size > 0 ? size : null,
      );
    } on FormatException {
      return null;
    }
  }

  /// Vrai si cette version mérite d'être proposée à qui tourne en
  /// [installedCode].
  ///
  /// **Strictement supérieur**, et sur le `versionCode` seul. Deux pièges
  /// qu'on évite ici :
  ///
  /// - comparer les `versionName` en texte fait passer « 0.10.0 » pour plus
  ///   ancien que « 0.9.0 » — l'ordre lexicographique n'est pas l'ordre des
  ///   versions ;
  /// - un `>=` proposerait éternellement la mise à jour qu'on vient
  ///   d'installer, et un build de dev en avance sur la prod se verrait offrir
  ///   un retour en arrière.
  bool isNewerThan(int installedCode) => versionCode > installedCode;

  @override
  String toString() => 'CompanionRelease($versionName+$versionCode)';
}
