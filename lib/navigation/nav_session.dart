import 'package:flutter/foundation.dart';

/// Le tracé que la page de navigation a laissé dans son stockage local.
///
/// Côté site, `navSession.ts` mémorise le tracé complet — géométrie, voicehints,
/// POI, repères — pour qu'un rechargement en pleine sortie reparte sur ce qu'on
/// suivait. L'appli n'a besoin que de quoi **le nommer** dans le sélecteur : le
/// tracé lui-même, elle ne le lit pas et ne saurait qu'en faire, c'est la page
/// qui le restaure toute seule quand on ouvre `/navigate` sans `fresh`.
///
/// D'où la lecture au plus juste dans le script injecté (nom, token, date) :
/// faire transiter la géométrie par le canal JavaScript, ce sont des mégaoctets
/// de JSON pour afficher une ligne de liste.
@immutable
class NavSessionSummary {
  const NavSessionSummary({
    required this.name,
    required this.token,
    required this.savedAt,
  });

  /// La clé du `localStorage`, telle qu'écrite par `navSession.ts`. **Changer
  /// l'une demande de changer l'autre** — il n'y a pas de contrat plus fort
  /// entre les deux dépôts que cette chaîne.
  static const storageKey = 'sportsScope.navSession';

  /// Au-delà, le site considère la séance finie et purge l'entrée à la
  /// prochaine ouverture. On applique la même limite ici plutôt que de proposer
  /// de reprendre un tracé que la page effacerait sous nos yeux.
  static const maxAge = Duration(hours: 12);

  /// Nom du tracé. Vide pour une destination ad hoc (« naviguer ici »), qui n'en
  /// a pas : l'affichage met alors un mot à la place, jamais une ligne nue.
  final String name;

  /// Token de partage du tracé, `null` pour une destination ad hoc — qui
  /// n'existe nulle part côté serveur, et ne se reprend donc que par le
  /// stockage de la page.
  final String? token;

  /// Dernière écriture par la page.
  final DateTime savedAt;

  /// Ce qu'on écrit dans le sélecteur.
  String get label => name.isEmpty ? 'Destination' : name;

  bool isFresh(DateTime now) => now.difference(savedAt) < maxAge;

  /// Lit ce que le script injecté a rapporté du `localStorage`.
  ///
  /// Rend `null` sur toute forme inattendue : une session illisible n'est pas
  /// une session, et proposer de reprendre un tracé qu'on n'a pas compris
  /// mènerait à une carte nue sans que personne n'ait rien demandé.
  static NavSessionSummary? parse(Object? raw, {DateTime? now}) {
    if (raw is! Map) return null;

    final savedAtMs = raw['t'];
    if (savedAtMs is! num) return null;

    final session = NavSessionSummary(
      name: raw['name'] is String ? raw['name'] as String : '',
      token: raw['token'] is String ? raw['token'] as String : null,
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs.toInt()),
    );

    // L'horodatage et l'horloge qu'on lui compare viennent du même téléphone :
    // la soustraction a un sens, contrairement à ce que vaudrait une date posée
    // par le serveur.
    return session.isFresh(now ?? DateTime.now()) ? session : null;
  }

  @override
  String toString() => 'NavSessionSummary($label, ${token ?? "ad hoc"})';
}
