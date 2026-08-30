import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Le registre des catégories de points d'intérêt ponctuels, recopié de
/// `app/javascript/poiCategories.ts` (dépôt site).
///
/// Un fac-similé, pas un contrat partagé au sens strict : le site pousse déjà
/// les POI décodés (`type` = un `serverType`, `pois` dans `nav_state`/
/// `nearby_pois.dart`) et applique lui-même le filtre. Ici on n'a besoin que du
/// libellé, de l'icône et de la couleur pour dessiner la feuille « POI à
/// proximité » et sa liste de cases. Quand le site ajoute une catégorie, elle
/// arrive quand même dans les messages : une catégorie inconnue retombe sur
/// [PoiCategory.unknown] (repère neutre) plutôt que de disparaître.
///
/// Les localités (`city`/`town`/`village`/`hamlet`) ne sont **pas** ici : ce
/// sont des lieux accrochés au tracé, jamais des POI ponctuels autour du
/// cycliste — le site ne les met pas dans `pois`.
@immutable
class PoiCategory {
  const PoiCategory({
    required this.key,
    required this.serverTypes,
    required this.label,
    required this.icon,
    required this.color,
  });

  /// La clé passée à `setPoiFilter` (identique à `key` côté site).
  final String key;

  /// Les valeurs possibles du champ `type` d'un POI reçu pour cette catégorie.
  final List<String> serverTypes;

  /// Libellé français — l'appli ne connaît que le français (voir les unités non
  /// traduites du tableau de bord).
  final String label;

  final FaIconData icon;
  final Color color;

  static const unknown = PoiCategory(
    key: '',
    serverTypes: [],
    label: 'Point d\'intérêt',
    icon: FontAwesomeIcons.locationDot,
    color: Color(0xFF6B7280),
  );
}

const List<PoiCategory> poiCategories = [
  PoiCategory(
    key: 'cemeteries',
    serverTypes: ['cemetery'],
    label: 'Cimetières',
    icon: FontAwesomeIcons.cross,
    color: Color(0xFF6B7280),
  ),
  PoiCategory(
    key: 'bakeries',
    serverTypes: ['bakery'],
    label: 'Boulangeries',
    icon: FontAwesomeIcons.breadSlice,
    color: Color(0xFFB45309),
  ),
  PoiCategory(
    key: 'water',
    serverTypes: ['water'],
    label: 'Points d\'eau',
    icon: FontAwesomeIcons.faucetDrip,
    color: Color(0xFF2563EB),
  ),
  PoiCategory(
    key: 'food',
    serverTypes: ['food'],
    label: 'Restaurants',
    icon: FontAwesomeIcons.utensils,
    color: Color(0xFFDC2626),
  ),
  PoiCategory(
    key: 'viewpoints',
    serverTypes: ['viewpoint'],
    label: 'Points de vue',
    icon: FontAwesomeIcons.binoculars,
    color: Color(0xFF7C3AED),
  ),
  PoiCategory(
    key: 'picnic',
    serverTypes: ['picnic'],
    label: 'Aires de pique-nique',
    icon: FontAwesomeIcons.tree,
    color: Color(0xFF15803D),
  ),
  PoiCategory(
    key: 'toilets',
    serverTypes: ['toilets'],
    label: 'Toilettes',
    icon: FontAwesomeIcons.restroom,
    color: Color(0xFF0891B2),
  ),
  PoiCategory(
    key: 'parking',
    serverTypes: ['parking'],
    label: 'Parkings',
    icon: FontAwesomeIcons.squareParking,
    color: Color(0xFF1D4ED8),
  ),
];

final Map<String, PoiCategory> _byServerType = {
  for (final category in poiCategories)
    for (final type in category.serverTypes) type: category,
};

final Map<String, PoiCategory> _byKey = {
  for (final category in poiCategories) category.key: category,
};

/// La catégorie d'un `type` de POI reçu du site, ou [PoiCategory.unknown].
PoiCategory poiCategoryForType(String type) =>
    _byServerType[type] ?? PoiCategory.unknown;

/// La catégorie d'une clé de filtre, ou `null` si cette version ne la connaît
/// pas (site plus récent).
PoiCategory? poiCategoryForKey(String key) => _byKey[key];
