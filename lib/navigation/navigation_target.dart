/// L'URL de l'application web, injectable au build :
/// `flutter run --dart-define=SPORTS_SCOPE_URL=http://192.168.1.20:3000`.
const sportsScopeBaseUrl = String.fromEnvironment(
  'SPORTS_SCOPE_URL',
  defaultValue: 'https://sports.logicraft.ch',
);

/// Ce qu'on va naviguer : un itinéraire partagé, la reprise de celui en cours,
/// ou rien (navigation libre).
///
/// Le token de partage est la seule clé dont l'appli a besoin : côté Rails la
/// navigation est adressée par lui et non par l'identifiant interne, ce qui
/// évite d'avoir à authentifier le téléphone.
class NavigationTarget {
  const NavigationTarget({
    this.shareToken,
    this.label,
    this.handoffToken,
    this.resume = false,
  });

  /// Partir sans tracé : la carte nue, et rien de ce qui traînait.
  const NavigationTarget.free() : this();

  /// Repartir sur le tracé que la page a gardé dans son stockage local, à
  /// l'endroit où on en était. Aucun token à donner : c'est la page qui sait
  /// quoi restaurer (voir `NavSessionSummary`), y compris une destination ad
  /// hoc qui n'existe nulle part côté serveur.
  const NavigationTarget.resume({String? label, String? handoffToken})
      : this(label: label, handoffToken: handoffToken, resume: true);

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

  /// Reprise du tracé mémorisé par la page, plutôt qu'un départ à neuf. N'a de
  /// sens que sans [shareToken] : demander un itinéraire précis, c'est déjà dire
  /// lequel on veut.
  final bool resume;

  bool get isFree => shareToken == null;

  Uri url({String baseUrl = sportsScopeBaseUrl}) {
    final base = Uri.parse(baseUrl);
    final path = isFree ? '/navigate' : '/routes/$shareToken/navigate';
    final destination = '${base.path}$path'.replaceAll('//', '/');

    // `fresh=1` est ce qui distingue les deux `/navigate`. Sans lui, la page
    // restaure le tracé de son `localStorage` — c'est le chemin de la reprise
    // après un rechargement, et c'était le bug de « Navigation libre », qui
    // rouvrait l'itinéraire de tout à l'heure au lieu de la carte nue.
    final fresh = isFree && !resume;

    if (handoffToken == null) {
      return base.replace(path: destination, query: fresh ? 'fresh=1' : null);
    }

    // Ouvrir la session AVANT la page, et pas après : la navigation lit les
    // préférences du compte au chargement (fond de carte, POI, itinéraires).
    // Arriver anonyme puis se connecter demanderait un rechargement.
    return base.replace(
      path: '${base.path}/auth/handoff'.replaceAll('//', '/'),
      queryParameters: {
        'token': handoffToken,
        'next': fresh ? '$destination?fresh=1' : destination,
      },
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

    // Un lien entrant sans token part toujours à neuf, jamais en reprise : on
    // ne sait pas ce que la page a en mémoire, et rouvrir l'itinéraire de tout
    // à l'heure parce qu'on a touché un lien serait la surprise qu'on vient de
    // corriger. La reprise ne s'offre que là où on a vraiment lu le stockage,
    // c'est-à-dire dans le sélecteur.
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
  String toString() => switch ((isFree, resume)) {
        (true, true) => 'NavigationTarget(reprise)',
        (true, false) => 'NavigationTarget(libre)',
        _ => 'NavigationTarget($shareToken)',
      };
}
