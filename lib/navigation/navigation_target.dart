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
  const NavigationTarget({this.shareToken, this.label, this.handoffToken});

  const NavigationTarget.free() : this();

  final String? shareToken;

  /// Nom affiché dans l'appli. Peut manquer : un lien partagé ne le porte pas.
  final String? label;

  /// Jeton de passage de session, posé par le site sur le lien « ouvrir dans
  /// l'application » quand on y est connecté.
  ///
  /// Chrome et le WebView ont deux pots de cookies distincts : sans ce jeton,
  /// toucher le bouton depuis un compte connecté rouvrirait la navigation en
  /// anonyme, et il faudrait se connecter une deuxième fois dans l'appli. Le
  /// jeton ne vaut qu'une fois et quelques minutes ; l'appli ne fait que le
  /// transmettre, c'est Rails qui l'échange contre une session
  /// (`SessionsController#handoff`).
  final String? handoffToken;

  bool get isFree => shareToken == null;

  Uri url({String baseUrl = sportsScopeBaseUrl}) {
    final base = Uri.parse(baseUrl);
    final path = isFree ? '/navigate' : '/routes/$shareToken/navigate';
    final destination = '${base.path}$path'.replaceAll('//', '/');

    if (handoffToken == null) return base.replace(path: destination);

    // Ouvrir la session AVANT la page, et pas après : la navigation lit les
    // préférences du compte au chargement (fond de carte, POI, itinéraires).
    // Arriver anonyme puis se connecter demanderait un rechargement.
    return base.replace(
      path: '${base.path}/auth/handoff'.replaceAll('//', '/'),
      queryParameters: {'token': handoffToken, 'next': destination},
    );
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
    // `?handoff=…` : présent sur les liens posés par le site pour un utilisateur
    // connecté, absent partout ailleurs (lien reçu par message, lien recopié).
    final handoff = uri.queryParameters['handoff'];

    if (uri.scheme == 'sportsscope') {
      // sportsscope://navigate/<token> : `navigate` est l'hôte, le token le
      // premier segment. Sans token, c'est la navigation libre.
      if (uri.host != 'navigate') return null;
      final token = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      return NavigationTarget(
        shareToken: token?.isEmpty == true ? null : token,
        handoffToken: handoff,
      );
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
      return NavigationTarget(handoffToken: handoff);
    }
    if (path.length == 3 &&
        path[0] == 'routes' &&
        path[2] == 'navigate' &&
        path[1].isNotEmpty) {
      return NavigationTarget(shareToken: path[1], handoffToken: handoff);
    }
    return null;
  }

  @override
  String toString() => isFree ? 'NavigationTarget(libre)' : 'NavigationTarget($shareToken)';
}
