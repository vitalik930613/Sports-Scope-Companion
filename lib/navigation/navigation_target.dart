/// L'URL de l'application web, injectable au build :
/// `flutter run --dart-define=SPORTS_SCOPE_URL=http://192.168.1.20:3000`.
const sportsScopeBaseUrl = String.fromEnvironment(
  'SPORTS_SCOPE_URL',
  defaultValue: 'https://sports.logicraft.ch',
);

/// Ce qu'on va naviguer : un itinéraire partagé, ou rien (navigation libre).
///
/// Le token de partage est la seule clé dont l'appli a besoin : côté Rails la
/// navigation est adressée par lui et non par l'identifiant interne, ce qui
/// évite d'avoir à authentifier le téléphone.
class NavigationTarget {
  const NavigationTarget({this.shareToken, this.label});

  const NavigationTarget.free() : this();

  final String? shareToken;

  /// Nom affiché dans l'appli. Peut manquer : un lien partagé ne le porte pas.
  final String? label;

  bool get isFree => shareToken == null;

  Uri url({String baseUrl = sportsScopeBaseUrl}) {
    final base = Uri.parse(baseUrl);
    final path = isFree ? '/navigate' : '/routes/$shareToken/navigate';
    return base.replace(path: '${base.path}$path'.replaceAll('//', '/'));
  }

  /// Reconnaît les liens qui doivent ouvrir la navigation.
  ///
  /// Deux formes acceptées :
  ///  - `sportsscope://navigate/<token>` — le schéma propre à l'appli, celui
  ///    que pose le bouton « Ouvrir dans l'appli » du site ;
  ///  - `https://<domaine>/routes/<token>/navigate` — l'URL réelle, pour que
  ///    n'importe quel lien partagé (message, e-mail) puisse aussi ouvrir
  ///    l'appli une fois les App Links vérifiés.
  ///
  /// Le préfixe de langue optionnel de Rails (`/fr/routes/…`) est toléré.
  /// Renvoie `null` si le lien ne concerne pas la navigation — au lecteur de
  /// décider quoi en faire, ici on ne devine pas.
  static NavigationTarget? parse(Uri uri) {
    if (uri.scheme == 'sportsscope') {
      // sportsscope://navigate/<token> : `navigate` est l'hôte, le token le
      // premier segment. Sans token, c'est la navigation libre.
      if (uri.host != 'navigate') return null;
      final token = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      return NavigationTarget(shareToken: token?.isEmpty == true ? null : token);
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    // Un éventuel préfixe de langue : /fr/routes/… ou /en/routes/…
    final path = segments.isNotEmpty && (segments.first == 'fr' || segments.first == 'en')
        ? segments.sublist(1)
        : segments;

    if (path.length == 1 && path.first == 'navigate') {
      return const NavigationTarget.free();
    }
    if (path.length == 3 &&
        path[0] == 'routes' &&
        path[2] == 'navigate' &&
        path[1].isNotEmpty) {
      return NavigationTarget(shareToken: path[1]);
    }
    return null;
  }

  @override
  String toString() => isFree ? 'NavigationTarget(libre)' : 'NavigationTarget($shareToken)';
}
