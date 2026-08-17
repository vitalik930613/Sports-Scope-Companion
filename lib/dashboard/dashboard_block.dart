import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../ble/sensor_profile.dart';
import 'companion_icons.dart';
import 'metric_id.dart';

/// Ce qu'on peut poser dans une page du tableau de bord, et **comment ça se
/// dessine**.
///
/// Le mode n'est pas une décoration : le même contenu ne tient pas de la même
/// façon dans un quart d'écran et dans une bande de deux cellules. Une
/// répartition par zone montre sa barre et sa légende quand elle a la place,
/// sa barre seule quand elle n'en a plus — plutôt que de déborder ou de
/// rapetisser jusqu'à l'illisible.
///
/// Hiérarchie scellée : le rendu s'écrit en `switch` exhaustif, et ajouter un
/// composant fait échouer la compilation là où il manque, plutôt que de
/// disparaître silencieusement de l'écran.
///
/// **Rien ici ne lève.** Même convention que les décodeurs GATT : une entrée
/// incomprise rend `null` et disparaît de la page, un mode inconnu retombe sur
/// le mode par défaut du composant. Le site peut être plus récent que l'appli,
/// et une page qui refuserait de se dessiner en pleine sortie serait le pire
/// résultat possible.
@immutable
sealed class DashboardBlock {
  const DashboardBlock({this.color, this.textColor});

  /// Couleur de fond de la carte, réglée dans l'éditeur — vaut pour n'importe
  /// quel genre de composant, contrairement à [MetricBlock.metric] par
  /// exemple qui est propre à un genre. `null` : la carte garde son fond
  /// habituel (couleur de zone si la mesure en porte une, gris des cartes
  /// sinon) — voir [BlockSurface] (`block_card.dart`).
  final Color? color;

  /// Couleur du texte principal de la carte. `null` : calculée pour rester
  /// lisible sur le fond réel de la carte ([color] s'il est réglé, sinon la
  /// couleur de zone), jamais blanc fixe — voir `foregroundOf`
  /// (`ui/zone_colors.dart`). Ne remplace jamais une couleur *sémantique*
  /// (palier de zone, tranche de pente, état radar, budget de charge) : ce
  /// sont des données, pas la surface du texte.
  final Color? textColor;

  /// `null` quand l'entrée ne décrit aucun composant connu.
  static DashboardBlock? parse(Object? raw) {
    if (raw is! Map) return null;

    final color = _colorOf(raw, 'color');
    final textColor = _colorOf(raw, 'text_color');

    return switch (raw['kind']) {
      'metric' => MetricBlock.parse(raw),
      'zones' => ZonesBlock.parse(raw),
      'averages' => AveragesBlock(
          mode: _modeOf(raw['mode'], AveragesMode.values),
          color: color,
          textColor: textColor,
        ),
      'lap_zones' => LapZonesBlock.parse(raw),
      'lap_averages' => LapAveragesBlock(
          mode: _modeOf(raw['mode'], AveragesMode.values),
          color: color,
          textColor: textColor,
        ),
      'lap_summary' => LapSummaryBlock(
          mode: _modeOf(raw['mode'], LapSummaryMode.values),
          color: color,
          textColor: textColor,
        ),
      'lap_selector' => LapSelectorBlock(color: color, textColor: textColor),
      'mark_lap' => MarkLapBlock(
          series: raw['series'] is String ? raw['series'] as String : 'default',
          mode: _modeOf(raw['mode'], MarkLapMode.values),
          color: color,
          textColor: textColor,
        ),
      'recording' => RecordingBlock(
          mode: _modeOf(raw['mode'], RecordingMode.values),
          color: color,
          textColor: textColor,
        ),
      'change_route' => ChangeRouteBlock(
          mode: _modeOf(raw['mode'], ChangeRouteMode.values),
          color: color,
          textColor: textColor,
        ),
      'clear_route' => ClearRouteBlock(
          mode: _modeOf(raw['mode'], ClearRouteMode.values),
          color: color,
          textColor: textColor,
        ),
      'route' => RouteBlock(
          mode: _modeOf(raw['mode'], RouteMode.values),
          color: color,
          textColor: textColor,
        ),
      'nav_state' => NavStateBlock(
          mode: _modeOf(raw['mode'], NavStateMode.values),
          color: color,
          textColor: textColor,
        ),
      'radar' => RadarBlock(
          mode: _modeOf(raw['mode'], RadarMode.values),
          color: color,
          textColor: textColor,
        ),
      'battery' => BatteryBlock(
          mode: _modeOf(raw['mode'], BatteryMode.values),
          sensor: _batterySensorOf(raw['sensor']),
          color: color,
          textColor: textColor,
        ),
      'precip_radar' => PrecipRadarBlock(color: color, textColor: textColor),
      'precip_forecast' => PrecipForecastBlock(color: color, textColor: textColor),
      'weather_forecast' => WeatherForecastBlock(color: color, textColor: textColor),
      'training_budget' => TrainingBudgetBlock(
          mode: _modeOf(raw['mode'], TrainingBudgetMode.values),
          color: color,
          textColor: textColor,
        ),
      'power_curve' => PowerCurveBlock(
          mode: _modeOf(raw['mode'], PowerCurveMode.values),
          color: color,
          textColor: textColor,
        ),
      'climb_list' => ClimbListBlock(
          mode: _modeOf(raw['mode'], ClimbListMode.values),
          color: color,
          textColor: textColor,
        ),
      'climb_profile' => ClimbProfileBlock(color: color, textColor: textColor),
      'altitude_profile' => AltitudeProfileBlock.parse(raw),
      'clock' => ClockBlock.parse(raw),
      'sleep' => SleepBlock(
          mode: _modeOf(raw['mode'], SleepMode.values),
          color: color,
          textColor: textColor,
        ),
      'bell' => BellBlock(
          mode: _modeOf(raw['mode'], BellMode.values),
          sound: _modeOf(raw['sound'], BellSound.values),
          color: color,
          textColor: textColor,
        ),
      'empty' => const EmptyBlock(),
      _ => null,
    };
  }

  /// Le mode nommé, ou **le premier de la liste** — qui est le mode par défaut
  /// du composant, celui qui suppose le plus de place et se lit le mieux.
  static T _modeOf<T extends BlockMode>(Object? raw, List<T> modes) {
    if (raw is String) {
      for (final mode in modes) {
        if (mode.key == raw) return mode;
      }
    }
    return modes.first;
  }

  /// Le capteur visé par `battery.sensor` — mêmes clés BLE que
  /// `SensorSettings.parse` (`heart_rate`, `power`, `cadence`, `gears`,
  /// `radar`) pour que le site n'ait qu'un seul vocabulaire à connaître, plus
  /// `phone` pour la batterie du téléphone lui-même, qui n'est pas un capteur
  /// BLE. `null` sur tout le reste, y compris une clé absente : c'est ce qui
  /// garde le comportement d'avant ce réglage (le pire pourcentage, tous
  /// appareils confondus, téléphone compris).
  static BatterySensor? _batterySensorOf(Object? raw) => switch (raw) {
        'heart_rate' => BatterySensor.heartRate,
        'power' => BatterySensor.power,
        'cadence' => BatterySensor.speedCadence,
        'gears' => BatterySensor.gears,
        'radar' => BatterySensor.radar,
        'phone' => BatterySensor.phone,
        _ => null,
      };

  /// La couleur écrite par le site sous [key] (`"color"`/`"text_color"`),
  /// `#rrggbb` uniquement — même format que `sanitize_hex_color` côté site
  /// (`companion_settings.rb`), qui garantit déjà cette forme, mais l'appli
  /// ne lui fait pas confiance pour autant (cf. tête de fichier : rien ici ne
  /// lève). `null` sur tout le reste, plutôt qu'une couleur devinée.
  static Color? _colorOf(Map<dynamic, dynamic> raw, String key) {
    final value = raw[key];
    if (value is! String) return null;

    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
    if (match == null) return null;

    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }
}

/// Le contrat commun des modes : une clé écrite à la main, pour que renommer
/// une valeur Dart ne casse pas les documents déjà servis par le site.
abstract mixin class BlockMode {
  String get key;
}

/// Une mesure du catalogue, seule dans sa cellule.
class MetricBlock extends DashboardBlock {
  const MetricBlock({
    required this.metric,
    this.layout = MetricLayout.fallback,
    this.format = DurationFormat.hm,
    this.icon,
    this.label,
    this.min,
    this.max,
    super.color,
    super.textColor,
  });

  final MetricId metric;

  /// Où se pose chaque élément (icône, étiquette, unité, chiffre, jauge) —
  /// voir [MetricLayout]. Remplace les cinq anciens `mode` (`big`, `compact`,
  /// `zone`, `gauge`, `dynamic_gauge`), qui n'existent plus que comme repli
  /// de migration (voir [parse]).
  final MetricLayout layout;

  /// N'a d'effet que sur une mesure de durée ([MetricId.duration],
  /// [MetricId.movingTime], [MetricId.pauseTime], [MetricId.routeEta]) —
  /// présent sur toute mesure comme [layout], mais silencieusement ignoré des
  /// autres, plutôt qu'un champ optionnel de plus à défaire au rendu.
  final DurationFormat format;

  /// L'icône personnalisée réglée dans l'éditeur, propre à ce bloc — `null` :
  /// [MetricId.icon] fait foi. N'a d'effet que si [layout] pose un jeton
  /// `icon` quelque part ; sinon réglée pour rien, comme un `min`/`max` sans
  /// jauge.
  final FaIconData? icon;

  /// Le libellé personnalisé réglé dans l'éditeur, propre à ce bloc — `null` :
  /// [MetricId.name] fait foi. Même repli qu'[icon] si [layout] ne pose pas de
  /// jeton `label` quelque part : réglé pour rien.
  final String? label;

  /// Bornes de la jauge à plage libre (une rangée de [layout] réglée sur
  /// `gauge`, mesure sans zones d'entraînement), réglées dans l'éditeur.
  /// `null` sur un document plus ancien, sans ce réglage, ou pour une jauge
  /// dynamique (sa plage se lit dans la sortie en cours, pas ici) :
  /// [MetricView] retombe alors sur la plage dynamique si la mesure en a une,
  /// sur l'absence de jauge sinon — jamais sur une plage inventée.
  final double? min;
  final double? max;

  /// `null` si la mesure nommée n'existe pas dans cette version : mieux vaut
  /// une cellule vide qu'une case qui affiche un tiret pour toujours.
  static MetricBlock? parse(Map<dynamic, dynamic> raw) {
    final metric = MetricId.fromKey(raw['metric']);
    if (metric == null) return null;

    // Les deux ensemble ou aucun : une seule borne ne dit rien, et le site ne
    // devrait jamais en écrire une sans l'autre — mais l'appli ne lui fait pas
    // confiance pour autant (cf. tête de fichier).
    final rawMin = _toDouble(raw['min']);
    final rawMax = _toDouble(raw['max']);
    final hasRange = rawMin != null && rawMax != null && rawMin < rawMax;

    // Migration : un document enregistré avant ce chantier, et jamais rouvert
    // dans l'éditeur depuis, n'a que `mode` — jamais `layout`. Même table que
    // `CompanionSettings::LEGACY_LAYOUTS` côté site, pour qu'il continue de
    // s'afficher exactement comme avant, sans qu'on ait à le retoucher.
    final layout = raw['layout'] == null
        ? MetricLayout.forLegacyMode(DashboardBlock._modeOf(raw['mode'], MetricMode.values))
        : MetricLayout.parse(raw['layout']);

    return MetricBlock(
      metric: metric,
      layout: layout,
      format: DashboardBlock._modeOf(raw['format'], DurationFormat.values),
      icon: companionIconFor(raw['icon'] is String ? raw['icon'] as String : null),
      label: raw['label'] is String && (raw['label'] as String).trim().isNotEmpty
          ? (raw['label'] as String).trim()
          : null,
      min: hasRange ? rawMin : null,
      max: hasRange ? rawMax : null,
      color: DashboardBlock._colorOf(raw, 'color'),
      textColor: DashboardBlock._colorOf(raw, 'text_color'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetricBlock &&
      other.metric == metric &&
      other.layout == layout &&
      other.format == format &&
      other.icon == icon &&
      other.label == label &&
      other.min == min &&
      other.max == max &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(
      metric, layout, format, icon, label, min, max, color, textColor);
}

double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;

/// Où se pose un élément d'un bloc `metric` : une rangée (`0`–[MetricLayout.maxRows]
/// exclu) et une colonne. Même contrat que les positions `"<rangée>-<colonne>"`
/// du document JSON (`CompanionSettings::LAYOUT_COLUMNS` côté site).
enum GridColumn { left, center, right }

@immutable
class GridPosition {
  const GridPosition(this.row, this.column);

  final int row;
  final GridColumn column;

  /// `null` si [raw] n'est pas une position valide — une rangée hors bornes,
  /// une colonne inconnue, ou pas une chaîne du tout.
  static GridPosition? parse(Object? raw) {
    if (raw is! String) return null;

    final parts = raw.split('-');
    if (parts.length != 2) return null;

    final row = int.tryParse(parts[0]);
    if (row == null || row < 0 || row >= MetricLayout.maxRows) return null;

    final column = switch (parts[1]) {
      'left' => GridColumn.left,
      'center' => GridColumn.center,
      'right' => GridColumn.right,
      _ => null,
    };
    if (column == null) return null;

    return GridPosition(row, column);
  }

  @override
  bool operator ==(Object other) =>
      other is GridPosition && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// Une annotation posée dans un coin d'un bloc `metric` — une mesure dérivée
/// (`speed_avg`, `hr_max`…) plus petite que le chiffre principal, avec son
/// propre repère (« MOY », « MAX »…). Voir [MetricLayout.secondary].
@immutable
class SecondaryMetricSlot {
  const SecondaryMetricSlot({required this.metric, required this.position, this.label});

  final MetricId metric;
  final GridPosition position;

  /// Le petit repère collé au chiffre — réglé dans l'éditeur. `null` : le
  /// rendu retombe sur une légende compacte déduite du suffixe de
  /// [metric.key] (`_avg` → « MOY », `_max` → « MAX », `_min` → « MIN »),
  /// jamais sur le nom complet de la mesure ([MetricId.name]), trop long pour
  /// un coin de carte.
  final String? label;

  /// `null` si `raw` ne décrit pas un slot exploitable — mesure inconnue de
  /// cette version, ou position absente/invalide. Même tolérance que le reste
  /// de ce fichier : rien ici ne lève.
  static SecondaryMetricSlot? parse(Object? raw) {
    if (raw is! Map) return null;

    final metric = MetricId.fromKey(raw['metric']);
    if (metric == null) return null;

    final position = GridPosition.parse(raw['position']);
    if (position == null) return null;

    final label = raw['label'];
    return SecondaryMetricSlot(
      metric: metric,
      position: position,
      label: label is String && label.trim().isNotEmpty ? label.trim() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SecondaryMetricSlot &&
      other.metric == metric &&
      other.position == position &&
      other.label == label;

  @override
  int get hashCode => Object.hash(metric, position, label);
}

/// La disposition d'un bloc `metric` : une grille à 3 colonnes et jusqu'à
/// [maxRows] rangées, où chaque élément se pose dans une case précise. Une
/// clé absente = élément masqué ; [value] est la seule obligatoire. La jauge
/// n'a pas de colonne — c'est une barre pleine largeur, pas un texte — donc
/// seulement une rangée ([gaugeRow]).
///
/// Remplace les cinq anciens `mode` d'un bloc `metric` (voir [forLegacyMode]
/// pour la migration d'un document plus ancien) — même contrat que
/// `CompanionSettings::LAYOUT_*`/`sanitize_layout_positions` côté site et
/// `MetricLayout`/`layoutRows` (`companionSettings.ts`).
@immutable
class MetricLayout {
  const MetricLayout({
    this.icon,
    this.label,
    this.unit,
    required this.value,
    this.gaugeRow,
    this.rowHeights = const {},
    this.secondary = const [],
  });

  final GridPosition? icon;
  final GridPosition? label;
  final GridPosition? unit;
  final GridPosition value;

  /// Les annotations min/moyenne/max posées dans les coins de la carte —
  /// voir [SecondaryMetricSlot]. Vide sur un document d'avant ce réglage,
  /// comme [rowHeights].
  final List<SecondaryMetricSlot> secondary;

  /// La rangée occupée par la jauge, `null` si aucune n'est posée. Sa nature
  /// (zones du cycliste, plage réglée, plage dynamique) se décide au rendu
  /// (`MetricView`), pas ici — voir [MetricBlock.min]/[MetricBlock.max].
  final int? gaugeRow;

  /// Le poids de chaque rangée dans le partage de la hauteur réelle de la
  /// case — voir [RowHeight]. Une rangée absente vaut [RowHeight.normal].
  final Map<int, RowHeight> rowHeights;

  RowHeight heightOf(int row) => rowHeights[row] ?? RowHeight.normal;

  /// Au-delà, une case ne serait plus lisible d'un coup d'œil en roulant —
  /// même borne que `CompanionSettings::MAX_LAYOUT_ROWS` côté site.
  static const maxRows = 4;

  /// Le repli d'avant ce chantier : chiffre plein cadre, unité en dessous —
  /// même valeur que `CompanionSettings::DEFAULT_METRIC_LAYOUT` (site) et
  /// `DEFAULT_METRIC_LAYOUT` (`companionSettings.ts`).
  static const fallback = MetricLayout(
    value: GridPosition(0, GridColumn.center),
    unit: GridPosition(1, GridColumn.center),
  );

  /// La disposition qu'un ancien `mode` dessinait — même table que
  /// `CompanionSettings::LEGACY_LAYOUTS` côté site. Utilisée en lecture
  /// seule, pour qu'un document enregistré avant ce chantier continue de
  /// s'afficher comme avant.
  static MetricLayout forLegacyMode(MetricMode mode) => switch (mode) {
        MetricMode.big => fallback,
        MetricMode.compact => const MetricLayout(
            icon: GridPosition(0, GridColumn.center),
            value: GridPosition(1, GridColumn.center),
            unit: GridPosition(2, GridColumn.center),
          ),
        MetricMode.zone => const MetricLayout(
            icon: GridPosition(0, GridColumn.center),
            label: GridPosition(0, GridColumn.center),
            value: GridPosition(1, GridColumn.center),
          ),
        MetricMode.gauge || MetricMode.dynamicGauge => const MetricLayout(
            value: GridPosition(0, GridColumn.center),
            gaugeRow: 1,
            unit: GridPosition(2, GridColumn.center),
          ),
      };

  /// Reconstruit une disposition depuis le document JSON — mêmes règles
  /// qu'en Ruby (`sanitize_layout_positions`) : une position invalide masque
  /// simplement son élément, la jauge évince ce qui partage sa rangée (dans
  /// les deux sens : elle-même ignorée si un autre élément a été lu en
  /// premier sur sa rangée n'a pas de sens ici puisqu'on lit tout d'un coup —
  /// c'est donc elle qui gagne), le chiffre est toujours présent.
  ///
  /// Ne sait pas encore si la jauge a un sens pour la mesure choisie — c'est
  /// [MetricBlock.parse] qui, comme `sanitize_block` côté site, la laisse
  /// intacte : sa nature (zones, plage réglée, plage dynamique) se décide au
  /// rendu, pas ici.
  static MetricLayout parse(Object? raw) {
    if (raw is! Map) return fallback;

    final gaugeRaw = raw['gauge'];
    final gaugeRow = gaugeRaw is String ? int.tryParse(gaugeRaw) : null;
    final validGaugeRow =
        gaugeRow != null && gaugeRow >= 0 && gaugeRow < maxRows ? gaugeRow : null;

    GridPosition? positionFor(String key) {
      final pos = GridPosition.parse(raw[key]);
      if (pos == null) return null;
      return (validGaugeRow != null && pos.row == validGaugeRow) ? null : pos;
    }

    final value = positionFor('value') ??
        GridPosition(validGaugeRow == 0 ? 1 : 0, GridColumn.center);

    final rowHeightsRaw = raw['row_heights'];
    final rowHeights = <int, RowHeight>{};
    if (rowHeightsRaw is Map) {
      for (final entry in rowHeightsRaw.entries) {
        final row = entry.key is String ? int.tryParse(entry.key as String) : null;
        if (row == null || row < 0 || row >= maxRows) continue;
        if (entry.value is! String) continue;

        final height = RowHeight.fromKey(entry.value as String);
        if (height != RowHeight.normal) rowHeights[row] = height;
      }
    }

    // Les positions déjà prises par icon/label/unit/value/la jauge : un slot
    // secondaire qui viserait l'une d'elles serait ignoré, « premier posé
    // gagne » comme partout ailleurs dans ce document (recouvrement de
    // grille, clé de profil dupliquée) — même règle que `sanitize_
    // layout_positions` côté site, appliquée ici indépendamment plutôt que de
    // faire confiance à un document déjà assaini.
    final claimed = <GridPosition>{
      if (positionFor('icon') case final p?) p,
      if (positionFor('label') case final p?) p,
      if (positionFor('unit') case final p?) p,
      value,
    };
    final secondary = <SecondaryMetricSlot>[];
    final secondaryRaw = raw['secondary'];
    if (secondaryRaw is List) {
      for (final entry in secondaryRaw) {
        final slot = SecondaryMetricSlot.parse(entry);
        if (slot == null) continue;
        if (validGaugeRow != null && slot.position.row == validGaugeRow) continue;
        if (!claimed.add(slot.position)) continue;
        secondary.add(slot);
      }
    }

    return MetricLayout(
      icon: positionFor('icon'),
      label: positionFor('label'),
      unit: positionFor('unit'),
      value: value,
      gaugeRow: validGaugeRow,
      rowHeights: rowHeights,
      secondary: secondary,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetricLayout &&
      other.icon == icon &&
      other.label == label &&
      other.unit == unit &&
      other.value == value &&
      other.gaugeRow == gaugeRow &&
      mapEquals(other.rowHeights, rowHeights) &&
      listEquals(other.secondary, secondary);

  @override
  int get hashCode => Object.hash(
        icon,
        label,
        unit,
        value,
        gaugeRow,
        // Une somme ou-exclusif plutôt que `Object.hashAll` : l'ordre des
        // entrées d'une `Map` n'a pas de sens à faire entrer dans le hash de
        // deux dispositions par ailleurs égales.
        rowHeights.entries.fold<int>(0, (acc, e) => acc ^ Object.hash(e.key, e.value)),
        Object.hashAll(secondary),
      );
}

/// Le poids d'une rangée dans le partage de la hauteur réelle de la case, et
/// le facteur d'échelle de son contenu — voir `CompanionSettings::
/// ROW_HEIGHTS` côté site. [normal] n'a pas de clé JSON : c'est la valeur par
/// défaut d'une rangée absente de [MetricLayout.rowHeights], jamais écrite
/// pour rester silencieuse.
///
/// **Les deux avancent ensemble**, et c'est ce qui compte ici : une rangée ne
/// reçoit plus de place que si son contenu (icône, texte, chiffre) grandit
/// d'autant — sinon une rangée « petite » à côté d'une « grande » se
/// retrouverait avec un contenu à sa taille habituelle dans une case bien
/// plus étroite que ce qu'il lui faut, et déborderait sur sa voisine plutôt
/// que de s'y ajuster ([Center] ne rogne rien).
enum RowHeight {
  small('small', 2, 0.5),
  normal(null, 4, 1),
  large('large', 8, 2);

  const RowHeight(this.key, this.weight, this.scale);

  final String? key;

  /// Le facteur `Expanded.flex` d'une rangée de texte/chiffre — même rapport
  /// que `ROW_HEIGHT_WEIGHT` côté site, et dans les mêmes proportions que
  /// [scale] (2 / 4 / 8, soit 0,5 / 1 / 2 fois la normale — de « petite » à
  /// « grande », le contenu quadruple). Sans effet sur une rangée de jauge,
  /// qui garde toujours sa hauteur naturelle.
  final int weight;

  /// Le facteur de taille de l'icône, de l'étiquette, de l'unité et du
  /// chiffre de cette rangée — même rapport que `ROW_HEIGHT_SCALE` côté
  /// site. C'est lui qui rend la rangée « plus en évidence », pas seulement
  /// la case qui la contient.
  final double scale;

  /// [normal] pour toute clé absente ou inconnue — même repli qu'un mode
  /// inconnu ailleurs dans ce fichier.
  static RowHeight fromKey(String? raw) => values.firstWhere((h) => h.key == raw, orElse: () => normal);
}

/// Les cinq anciens `mode` d'un bloc `metric` — plus lus qu'une seule fois,
/// pour migrer un document enregistré avant ce chantier ([MetricLayout.
/// forLegacyMode]). [MetricBlock] ne porte plus de `mode` : sa disposition se
/// compose librement ([MetricLayout]).
enum MetricMode with BlockMode {
  /// Le chiffre plein cadre : ce qu'on lit à 30 km/h sans quitter la route des
  /// yeux. Mode par défaut, donc en tête.
  big('big'),

  /// Icône, valeur, unité — la mise en forme de `MetricTile`, pour les cellules
  /// où l'on tient plusieurs mesures.
  compact('compact'),

  /// Une jauge remplie jusqu'à la mesure, quand ce qui compte est la position
  /// dans la plage plutôt que le chiffre exact.
  gauge('gauge'),

  /// L'aplat de la zone du moment, avec la mesure dessus.
  zone('zone'),

  /// Un curseur en position continue sur une plage qui n'est **pas** réglée
  /// dans l'éditeur : le min et le max observés depuis le départ de la sortie
  /// (cadence, cardio, puissance, vitesse, pente), ou la progression vers
  /// l'itinéraire chargé (distance, durée). Contrairement à [gauge], la plage
  /// n'existe qu'en roulant — voir [MetricId.liveRangeOf].
  dynamicGauge('dynamic_gauge');

  const MetricMode(this.key);

  @override
  final String key;
}

/// Comment une mesure de durée écrit ses secondes. `hm` en tête : c'est le
/// format d'avant ce réglage, donc celui sur lequel un document sans cette clé
/// retombe.
enum DurationFormat with BlockMode {
  /// `04:12` — la seconde n'est pas écrite.
  hm('hm'),

  /// `04:12:07` — la seconde compte.
  hms('hms');

  const DurationFormat(this.key);

  @override
  final String key;
}

/// Le temps passé par zone depuis le départ, cardio ou puissance.
class ZonesBlock extends DashboardBlock {
  const ZonesBlock({
    required this.source,
    this.mode = ZonesMode.bar,
    super.color,
    super.textColor,
  });

  final ZonesSource source;
  final ZonesMode mode;

  static ZonesBlock parse(Map<dynamic, dynamic> raw) => ZonesBlock(
        source: switch (raw['source']) {
          'power' => ZonesSource.power,
          // Le cardio par défaut : c'est la répartition qui existe même sans
          // capteur de puissance.
          _ => ZonesSource.hr,
        },
        mode: DashboardBlock._modeOf(raw['mode'], ZonesMode.values),
        color: DashboardBlock._colorOf(raw, 'color'),
        textColor: DashboardBlock._colorOf(raw, 'text_color'),
      );

  @override
  bool operator ==(Object other) =>
      other is ZonesBlock &&
      other.source == source &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(source, mode, color, textColor);
}

enum ZonesSource { hr, power }

enum ZonesMode with BlockMode {
  /// La barre et sa légende, une ligne par zone. Ce qu'on lit à l'arrêt.
  bar('bar'),

  /// La barre seule : elle garde toute son information — une proportion se lit
  /// dans une longueur partagée — et tient dans la hauteur d'une cellule.
  barOnly('bar_only'),

  /// La légende seule, quand la barre est déjà ailleurs sur la page.
  legend('legend');

  const ZonesMode(this.key);

  @override
  final String key;
}

/// Le temps passé par zone, mais **depuis le début du tour sélectionné**, pas
/// depuis le départ de la sortie.
///
/// Même contenu que [ZonesBlock], et volontairement une classe à part plutôt
/// qu'un paramètre « depuis quand » sur celui-ci : ce bloc n'a de sens que sur
/// une page qui porte un tour sélectionné ([LapListPageSpec.series]), là où
/// [ZonesBlock] peut se poser n'importe où.
class LapZonesBlock extends DashboardBlock {
  const LapZonesBlock({
    required this.source,
    this.mode = ZonesMode.bar,
    super.color,
    super.textColor,
  });

  final ZonesSource source;
  final ZonesMode mode;

  static LapZonesBlock parse(Map<dynamic, dynamic> raw) => LapZonesBlock(
        source: switch (raw['source']) {
          'power' => ZonesSource.power,
          _ => ZonesSource.hr,
        },
        mode: DashboardBlock._modeOf(raw['mode'], ZonesMode.values),
        color: DashboardBlock._colorOf(raw, 'color'),
        textColor: DashboardBlock._colorOf(raw, 'text_color'),
      );

  @override
  bool operator ==(Object other) =>
      other is LapZonesBlock &&
      other.source == source &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(source, mode, color, textColor);
}

/// Les moyennes de la sortie : cardio, puissance, cadence, D+, calories.
class AveragesBlock extends DashboardBlock {
  const AveragesBlock({
    this.mode = AveragesMode.cards,
    super.color,
    super.textColor,
  });

  final AveragesMode mode;

  @override
  bool operator ==(Object other) =>
      other is AveragesBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum AveragesMode with BlockMode {
  cards('cards'),
  list('list');

  const AveragesMode(this.key);

  @override
  final String key;
}

/// Les moyennes, mais du tour sélectionné plutôt que de la sortie entière.
/// Même remarque que [LapZonesBlock] : une classe à part parce qu'elle n'a de
/// sens que sur une page de tours.
class LapAveragesBlock extends DashboardBlock {
  const LapAveragesBlock({
    this.mode = AveragesMode.cards,
    super.color,
    super.textColor,
  });

  final AveragesMode mode;

  @override
  bool operator ==(Object other) =>
      other is LapAveragesBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

/// La courbe de puissance : la meilleure moyenne tenue depuis le départ, par
/// durée (`RideStats.powerCurveW`) — 5 s à 90 min. Pas de variante « tour » :
/// un tour dure rarement 90 minutes, et la question qu'on pose à cette courbe
/// (« qu'ai-je de mieux tenu ») porte sur la sortie entière.
class PowerCurveBlock extends DashboardBlock {
  const PowerCurveBlock({
    this.mode = PowerCurveMode.table,
    super.color,
    super.textColor,
  });

  final PowerCurveMode mode;

  @override
  bool operator ==(Object other) =>
      other is PowerCurveBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum PowerCurveMode with BlockMode {
  /// Une ligne par durée, la meilleure moyenne à droite — ce qu'on relit à
  /// l'arrêt, chiffre par chiffre. Mode par défaut : c'est lui qui reste
  /// lisible même dans une case étroite ([StatCard] s'y réduit déjà).
  table('table'),

  /// La même courbe en graphique, durée en abscisse (échelle log — 5 s et
  /// 90 min ne se lisent pas sur la même règle), puissance en ordonnée.
  chart('chart');

  const PowerCurveMode(this.key);

  @override
  final String key;
}

/// Le bilan du tour sélectionné : durée, distance, D+, calories, TSS — ce
/// qu'on demanderait d'un tour entier plutôt qu'à une seule mesure. Le TSS
/// suit `rideTss` (`training/ride_load.dart`), déjà générique sur n'importe
/// quelle `RideStats`, donc valable tel quel sur celle d'un tour.
class LapSummaryBlock extends DashboardBlock {
  const LapSummaryBlock({
    this.mode = LapSummaryMode.cards,
    super.color,
    super.textColor,
  });

  final LapSummaryMode mode;

  @override
  bool operator ==(Object other) =>
      other is LapSummaryBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum LapSummaryMode with BlockMode {
  cards('cards'),
  list('list');
  const LapSummaryMode(this.key);

  @override
  final String key;
}

/// La liste déroulante qui choisit le tour affiché par les autres composants
/// d'une page Tours ([LapZonesBlock], [LapAveragesBlock], [LapSummaryBlock]).
///
/// **Un composant placé comme un autre, et non un en-tête imposé.** La
/// version d'avant le posait d'office au-dessus de la page ; la hauteur
/// qu'elle prenait n'était alors comptée nulle part, et une page Tours en
/// grille se retrouvait avec moins de place que ce que l'éditeur avait
/// composé — la grille semblait décalée une fois sur le téléphone. En le
/// rendant plaçable comme `lap_summary` ou `metric`, la page qui le porte
/// tient tout entière dans `rows` × `cols` (ou dans sa liste), sans rien caché
/// que l'éditeur ignorerait.
///
/// **Absent, la page reste utilisable** : elle montre alors toujours le tour
/// le plus récent, sans rien à choisir — la même valeur de repli qu'avant
/// qu'un choix explicite n'existe (`_selectedIndex ?? laps.length - 1`, cf.
/// `LapListBody`).
class LapSelectorBlock extends DashboardBlock {
  const LapSelectorBlock({super.color, super.textColor});

  @override
  bool operator ==(Object other) =>
      other is LapSelectorBlock &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(color, textColor);
}

/// Démarrer, suspendre, reprendre l'enregistrement.
class RecordingBlock extends DashboardBlock {
  const RecordingBlock({
    this.mode = RecordingMode.full,
    super.color,
    super.textColor,
  });

  final RecordingMode mode;

  @override
  bool operator ==(Object other) =>
      other is RecordingBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum RecordingMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const RecordingMode(this.key);

  @override
  final String key;
}

/// Marquer un tour : clôt le tour courant d'une série et en ouvre un nouveau.
///
/// Peut se poser sur n'importe quelle page, pas seulement une page de tours —
/// c'est en roulant, entre deux mesures, qu'on veut marquer un tour. [series]
/// dit **dans quelle série** ce bouton marque un tour ; plusieurs boutons de
/// séries différentes tournent sans se fermer l'une l'autre (voir
/// `RideRecorder.markLap`). `'default'` sans configuration : c'est aussi la
/// seule série que l'export `.fit` sait porter, le format n'ayant qu'une
/// hiérarchie de tours.
class MarkLapBlock extends DashboardBlock {
  const MarkLapBlock({
    this.series = 'default',
    this.mode = MarkLapMode.full,
    super.color,
    super.textColor,
  });

  final String series;
  final MarkLapMode mode;

  @override
  bool operator ==(Object other) =>
      other is MarkLapBlock &&
      other.series == series &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(series, mode, color, textColor);
}

enum MarkLapMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const MarkLapMode(this.key);

  @override
  final String key;
}

/// Choisir un autre itinéraire sans quitter la sortie.
///
/// Même geste que « Choisir un autre itinéraire » du menu ⋮
/// (`DashboardPage._actionsMenu`), posé directement sur une page plutôt que
/// rangé dans un menu qu'on n'ouvre presque jamais.
class ChangeRouteBlock extends DashboardBlock {
  const ChangeRouteBlock({
    this.mode = ChangeRouteMode.full,
    super.color,
    super.textColor,
  });

  final ChangeRouteMode mode;

  @override
  bool operator ==(Object other) =>
      other is ChangeRouteBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum ChangeRouteMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const ChangeRouteMode(this.key);

  @override
  final String key;
}

/// Retirer le tracé qu'on suit, sans quitter la sortie.
///
/// Même geste que « Retirer l'itinéraire » du menu ⋮. Désactivé — jamais
/// masqué — tant qu'aucun tracé n'est suivi : c'est un bouton qu'on a posé
/// exprès sur sa page, et le faire disparaître ferait chercher une case vide
/// plutôt qu'un bouton grisé qui explique pourquoi il ne répond pas.
class ClearRouteBlock extends DashboardBlock {
  const ClearRouteBlock({
    this.mode = ClearRouteMode.full,
    super.color,
    super.textColor,
  });

  final ClearRouteMode mode;

  @override
  bool operator ==(Object other) =>
      other is ClearRouteBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum ClearRouteMode with BlockMode {
  full('full'),
  compact('compact');

  const ClearRouteMode(this.key);

  @override
  final String key;
}

/// [ChangeRouteBlock] et [ClearRouteBlock], combinés en un seul bouton.
///
/// C'est l'état de la navigation qui décide lequel des deux gestes il pose —
/// retirer le tracé suivi s'il y en a un, en choisir un sinon. Gardé à côté
/// des deux commandes séparées et non à leur place : un profil déjà composé
/// avec elles ne doit rien perdre à l'enregistrement (`CompanionSettings`,
/// site).
///
/// Jamais désactivé, contrairement à [ClearRouteBlock] seul : hors tracé, le
/// bouton propose déjà le geste qui en pose un plutôt que de se griser sans
/// rien pouvoir faire.
class RouteBlock extends DashboardBlock {
  const RouteBlock({
    this.mode = RouteMode.full,
    super.color,
    super.textColor,
  });

  final RouteMode mode;

  @override
  bool operator ==(Object other) =>
      other is RouteBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum RouteMode with BlockMode {
  full('full'),
  compact('compact');

  const RouteMode(this.key);

  @override
  final String key;
}

/// Met la carte en veille : voile noir et rétroéclairage à 1 %, comme un appui
/// long sur la carte sait déjà le faire — mais depuis une page de données qui
/// n'a pas la carte sous les yeux. Le bouton ramène donc d'abord le cycliste
/// sur la carte (`RideShellPage._sleep`), puis demande au site d'entrer en
/// veille lui-même (`NavigationWebController.requestSleep`), par le même
/// chemin que l'appui long — pas de voile ni de logique de veille propres à
/// l'appli, qui n'a jamais dessiné sa propre veille depuis le retrait de
/// `lib/sleep/` (voir « La veille par appui long, sur la carte seulement »).
///
/// Sans effet sur un profil sans carte : voir `RideShellPage.onSleep`.
class SleepBlock extends DashboardBlock {
  const SleepBlock({
    this.mode = SleepMode.full,
    super.color,
    super.textColor,
  });

  final SleepMode mode;

  @override
  bool operator ==(Object other) =>
      other is SleepBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum SleepMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const SleepMode(this.key);

  @override
  final String key;
}

/// Fait sonner fort le téléphone — son et vibration au flux d'alarme, pour
/// traverser le mode silencieux/Ne pas déranger comme le ferait un réveil,
/// plutôt que le volume média qui s'y tairait. Utile pour le retrouver dans
/// un sac ou une poche.
///
/// Autonome comme [MarkLapBlock] : ni la sortie enregistrée ni la carte n'ont
/// besoin de savoir qu'il sonne, contrairement à [SleepBlock] qui doit
/// traverser `RideShellPage` pour ramener le cycliste sur la carte. Sonne
/// jusqu'au prochain tap, avec un arrêt de sécurité — voir [BellControl]
/// (`bell_block.dart`).
class BellBlock extends DashboardBlock {
  const BellBlock({
    this.mode = BellMode.full,
    this.sound = BellSound.bell,
    super.color,
    super.textColor,
  });

  final BellMode mode;

  /// Ce que joue le bouton — voir [BellSound].
  final BellSound sound;

  @override
  bool operator ==(Object other) =>
      other is BellBlock &&
      other.mode == mode &&
      other.sound == sound &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, sound, color, textColor);
}

enum BellMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const BellMode(this.key);

  @override
  final String key;
}

/// Ce que sonne [BellBlock] — même liste que `CompanionSettings::BELL_SOUNDS`
/// côté site. `bell` en tête : une sonnette classique, le repli d'un document
/// qui ne connaît pas encore `horn`/`booster`.
enum BellSound with BlockMode {
  bell('bell'),

  /// Le klaxon deux tons des voitures de la caravane du Tour de France —
  /// choisi pour être méconnaissable avec les autres alertes de l'appli
  /// (radar, virages), pas seulement fort.
  horn('horn'),

  /// Le plus long des trois sons (~6 s) — voir le minuteur de secours de
  /// `BellPlayer` (`ride/blocks/bell_player.dart`), calé dessus.
  booster('booster');

  const BellSound(this.key);

  @override
  final String key;
}

/// Ce que la page web raconte d'elle-même. Sans carte dans le profil, il n'y a
/// pas de page pour le dire : le bloc affiche alors qu'il n'attend rien.
class NavStateBlock extends DashboardBlock {
  const NavStateBlock({
    this.mode = NavStateMode.full,
    super.color,
    super.textColor,
  });

  final NavStateMode mode;

  @override
  bool operator ==(Object other) =>
      other is NavStateBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum NavStateMode with BlockMode {
  full('full'),
  compact('compact');

  const NavStateMode(this.key);

  @override
  final String key;
}

/// Le radar arrière. Ni « voie libre » ni tiret quand il est absent : pas de
/// radar n'est pas une route dégagée, et le bloc le dit.
class RadarBlock extends DashboardBlock {
  const RadarBlock({
    this.mode = RadarMode.distance,
    super.color,
    super.textColor,
  });

  final RadarMode mode;

  @override
  bool operator ==(Object other) =>
      other is RadarBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum RadarMode with BlockMode {
  /// Les mètres du véhicule le plus proche, en gros.
  distance('distance'),

  /// Les mêmes mètres, sans l'icône ni le `×N` : rien que le chiffre, pour la
  /// cellule qui n'a pas la hauteur d'en placer deux lignes.
  compact('compact'),

  /// Le compte des véhicules suivis : une icône, et le nombre à côté. Pour qui
  /// veut savoir combien remontent, pas à quelle distance est le premier.
  count('count'),

  /// Une icône par véhicule suivi — le compte redit sans chiffre, à l'endroit
  /// où l'on préfère compter d'un coup d'œil que lire un nombre.
  icons('icons'),

  /// Un simple carré de couleur, sans chiffre ni icône : orange pour une
  /// voiture détectée, rouge pour une voiture proche. Ce qui se lit le plus
  /// vite du coin de l'œil, pour la plus petite case de la grille.
  gauge('gauge');

  const RadarMode(this.key);

  @override
  final String key;
}

/// L'état des batteries des capteurs BLE connus, et de celle du téléphone
/// lui-même. Jamais coupé par le profil (voir `SensorSettings.allows`) : pas
/// de branche « profil éteint » à dessiner, contrairement à [RadarBlock].
class BatteryBlock extends DashboardBlock {
  const BatteryBlock({
    this.mode = BatteryMode.list,
    this.sensor,
    super.color,
    super.textColor,
  });

  final BatteryMode mode;

  /// En mode [BatteryMode.compact], restreint le pire pourcentage à ce
  /// capteur-là plutôt qu'à tous les appareils connus (téléphone compris) —
  /// la case n'a la place que pour un chiffre, et « le pire de tous » n'est
  /// pas toujours celui qu'on veut y surveiller (le capteur de puissance, par
  /// exemple, plutôt que la ceinture cardio posée sur la table depuis la
  /// dernière sortie). `null` : comportement d'avant ce réglage, tous
  /// appareils confondus. Sans effet en mode [BatteryMode.list], qui les
  /// liste déjà tous.
  final BatterySensor? sensor;

  @override
  bool operator ==(Object other) =>
      other is BatteryBlock &&
      other.mode == mode &&
      other.sensor == sensor &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, sensor, color, textColor);
}

enum BatteryMode with BlockMode {
  /// Une ligne par appareil connu — icône, libellé, pourcentage.
  list('list'),

  /// Le pire pourcentage connu, un seul chiffre : pour la case qui n'a pas la
  /// place d'en lister plusieurs.
  compact('compact');

  const BatteryMode(this.key);

  @override
  final String key;
}

/// Ce que le mode compact d'un bloc `battery` peut viser : un capteur BLE
/// connu, ou la batterie du téléphone lui-même — pas un [SensorKind], qui ne
/// connaît que le BLE et n'a rien à dire d'un appareil qui n'en est pas un.
enum BatterySensor {
  heartRate(SensorKind.heartRate),
  power(SensorKind.power),
  speedCadence(SensorKind.speedCadence),
  gears(SensorKind.gears),
  radar(SensorKind.radar),

  /// `null` : n'a pas de capacité BLE correspondante, voir
  /// `BatteryStatus.isPhone`.
  phone(null);

  const BatterySensor(this.sensorKind);

  /// `null` pour [phone], seul cas sans capteur BLE derrière.
  final SensorKind? sensorKind;
}

/// L'animation radar des précipitations (RainViewer), centrée sur la position
/// GPS courante : passé récent puis prévision courte ("nowcast"), en boucle.
///
/// Un seul mode — rien à faire varier, le dessin (tuiles + repère central) ne
/// change pas selon la case, seule son échelle. Contrairement à
/// [TrainingBudgetBlock]/[ClimbListBlock], la donnée ne dépend pas de la page
/// de navigation : le GPS suffit ([GpsSource], via [MetricSources.recorder]),
/// donc un profil de home-trainer sans WebView peut quand même le poser — il
/// affichera simplement l'état "pas de GPS" sans capteur de position.
class PrecipRadarBlock extends DashboardBlock {
  const PrecipRadarBlock({super.color, super.textColor});

  @override
  bool operator ==(Object other) =>
      other is PrecipRadarBlock &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(color, textColor);
}

/// La prévision de précipitations à 15 minutes (Open-Meteo), pour la position
/// GPS courante : une frise de barres sur les prochaines heures, et une
/// phrase qui dit si une averse arrive et dans combien de temps.
///
/// Un seul mode, même raison que [PrecipRadarBlock] : rien à faire varier
/// selon la case. Contrairement au radar RainViewer — qu'on lit à l'œil, le
/// système qui approche sur une carte — ce bloc répond directement à la
/// question en chiffres ; la donnée vient du GPS et non de la page de
/// navigation, donc un profil de home-trainer sans WebView peut quand même le
/// poser (il affichera l'état "pas de GPS", comme [PrecipRadarBlock]).
class PrecipForecastBlock extends DashboardBlock {
  const PrecipForecastBlock({super.color, super.textColor});

  @override
  bool operator ==(Object other) =>
      other is PrecipForecastBlock &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(color, textColor);
}

/// Les prévisions météo horaires (Open-Meteo), pour la position GPS
/// courante : température et vent en courbes, précipitations en barres, sur
/// les six prochaines heures.
///
/// Un seul mode, même raison que [PrecipRadarBlock]/[PrecipForecastBlock] :
/// rien à faire varier selon la case. Distinct de [PrecipForecastBlock], qui
/// ne regarde que les précipitations sur 6h à 15 min de pas pour répondre à
/// « une averse arrive-t-elle bientôt ? » — celui-ci donne la tendance des
/// heures qui viennent. La donnée vient du GPS et non de la page de navigation,
/// donc un profil de home-trainer sans WebView peut quand même le poser (il
/// affichera l'état "pas de GPS", comme les deux autres).
class WeatherForecastBlock extends DashboardBlock {
  const WeatherForecastBlock({super.color, super.textColor});

  @override
  bool operator ==(Object other) =>
      other is WeatherForecastBlock &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(color, textColor);
}

/// L'heure courante.
///
/// **La seule case du tableau de bord qui ne dépend d'aucun capteur ni de
/// l'enregistreur** : elle tourne même hors sortie, contrairement à `duration`
/// (`MetricId`) qui n'existe qu'en enregistrant. Ça la sort du catalogue
/// `MetricId`/`MetricSources`, qui n'existent que pour les mesures issues de ces
/// sources — d'où un `DashboardBlock` à part plutôt qu'une entrée de plus au
/// catalogue.
class ClockBlock extends DashboardBlock {
  const ClockBlock({
    this.mode = ClockMode.hm,
    this.layout = const MetricLayout(value: GridPosition(0, GridColumn.center)),
    this.icon,
    super.color,
    super.textColor,
  });

  final ClockMode mode;

  /// Où se posent l'icône, l'étiquette et le chiffre — même grille qu'un bloc
  /// `metric` ([MetricLayout]), réglable comme lui. **Jamais d'`unit` ni de
  /// `gaugeRow`** : une horloge n'a ni l'un ni l'autre, contrairement à une
  /// mesure qui peut y avoir droit selon son genre — [parse] les retire même
  /// si le document en portait.
  final MetricLayout layout;

  /// L'icône personnalisée réglée dans l'éditeur — même contrat que
  /// [MetricBlock.icon]. `null` : [ClockCard] retombe sur son icône par
  /// défaut, faute de [MetricId] pour en porter une.
  final FaIconData? icon;

  static ClockBlock parse(Map<dynamic, dynamic> raw) {
    final parsed = raw['layout'] == null
        ? const MetricLayout(value: GridPosition(0, GridColumn.center))
        : MetricLayout.parse(raw['layout']);
    // Ni jauge ni unité pour une horloge : on ne garde que ce que ClockCard
    // sait dessiner, plutôt que de faire confiance à un document qui en
    // porterait plus — même convention que le reste du fichier (rien ne lève,
    // un réglage sans effet est ignoré et non refusé).
    final layout = MetricLayout(
      icon: parsed.icon,
      label: parsed.label,
      value: parsed.value,
      rowHeights: parsed.rowHeights,
    );
    return ClockBlock(
      mode: DashboardBlock._modeOf(raw['mode'], ClockMode.values),
      layout: layout,
      icon: companionIconFor(raw['icon'] is String ? raw['icon'] as String : null),
      color: DashboardBlock._colorOf(raw, 'color'),
      textColor: DashboardBlock._colorOf(raw, 'text_color'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClockBlock &&
      other.mode == mode &&
      other.layout == layout &&
      other.icon == icon &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, layout, icon, color, textColor);
}

enum ClockMode with BlockMode {
  /// `14:03` — ce qu'on lit d'un coup d'œil en roulant. Mode par défaut.
  hm('hm'),

  /// `14:03:07`, la seconde comptée.
  hms('hms');

  const ClockMode(this.key);

  @override
  final String key;
}

/// Le budget de charge : ce qu'il reste à faire, et jusqu'où on peut aller.
///
/// **Le seul composant dont la donnée ne vient pas des capteurs.** Elle est
/// calculée par le site — qui seul a l'historique des sorties, l'objectif
/// d'entraînement et la cible de la semaine — et poussée par la page de
/// navigation. Un profil sans carte n'en recevra donc jamais : il n'y a pas de
/// WebView pour la porter, et le composant le dit au lieu d'afficher des zéros.
class TrainingBudgetBlock extends DashboardBlock {
  const TrainingBudgetBlock({
    this.mode = TrainingBudgetMode.day,
    super.color,
    super.textColor,
  });

  final TrainingBudgetMode mode;

  @override
  bool operator ==(Object other) =>
      other is TrainingBudgetBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum TrainingBudgetMode with BlockMode {
  /// Aujourd'hui : ce qui est déjà encaissé plus la sortie en cours, la cible du
  /// jour, le plafond que la fatigue autorise. Mode par défaut, donc en tête —
  /// c'est celui qui répond à « je continue ou je rentre ? », la question qu'on
  /// se pose au guidon. La semaine, elle, se regarde à l'arrêt.
  day('day'),

  /// La semaine : la cible, ce qui est fait depuis lundi, ce qui est déjà prévu
  /// sur les jours à venir, ce qu'il reste à placer.
  week('week');

  const TrainingBudgetMode(this.key);

  @override
  final String key;
}

/// La liste des cols du tracé, avec un repère « en cours / prochain ».
///
/// Vient de la page comme [NavStateBlock] et [TrainingBudgetBlock], pas d'un
/// capteur — donc absent sans carte dans le profil, comme eux (voir
/// `route_climbs.dart` : sans carte, personne n'alimente la liste).
class ClimbListBlock extends DashboardBlock {
  const ClimbListBlock({
    this.mode = ClimbListMode.full,
    super.color,
    super.textColor,
  });

  final ClimbListMode mode;

  @override
  bool operator ==(Object other) =>
      other is ClimbListBlock &&
      other.mode == mode &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(mode, color, textColor);
}

enum ClimbListMode with BlockMode {
  /// La liste entière, une ligne par col — ce qu'on lit à l'arrêt ou sur une
  /// page qui défile. Mode par défaut, donc en tête.
  full('full'),

  /// Une seule ligne : le col en cours, ou le prochain à venir. Pour la case
  /// de grille qui n'a la place que d'une phrase.
  compact('compact');

  const ClimbListMode(this.key);

  @override
  final String key;
}

/// Le profil gradué du col en cours, en graphique — même dessin que
/// [ClimbProfileOverlay] (posé sur la carte, sur tap du badge de col), mais
/// composable comme un bloc de page ordinaire.
///
/// Un seul mode, même raison que [PrecipRadarBlock]/[WeatherForecastBlock] :
/// le graphique remplit toute la case, rien à faire varier selon le mode.
///
/// Vient de la page comme [ClimbListBlock]/[TrainingBudgetBlock], pas d'un
/// capteur — donc absent sans carte dans le profil (voir `climb_profile.dart`
/// : sans carte, personne n'alimente le profil). Hors col en cours, la carte
/// le dit plutôt que de garder le graphique d'un col déjà terminé.
class ClimbProfileBlock extends DashboardBlock {
  const ClimbProfileBlock({super.color, super.textColor});

  @override
  bool operator ==(Object other) =>
      other is ClimbProfileBlock &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(color, textColor);
}

/// Le profil d'altitude de toute la sortie, en graphique — deux allures selon
/// le contexte, décidées par `AltitudeProfileCard` et non par ce bloc : un
/// tracé chargé donne le profil du parcours entier (fait/restant, même dessin
/// que [ClimbProfileBlock] sur toute la distance), sans tracé le profil de ce
/// qui a été effectivement parcouru.
///
/// Un seul mode, même raison que [ClimbProfileBlock] : le graphique remplit
/// toute la case.
///
/// Contrairement à [ClimbListBlock]/[ClimbProfileBlock]/[TrainingBudgetBlock],
/// **ne dépend pas forcément d'une page web** : sans tracé, il se rabat sur
/// `RideRecorder.elevationTrack`, alimenté par les capteurs du téléphone —
/// voir `AltitudeProfileCard`.
class AltitudeProfileBlock extends DashboardBlock {
  const AltitudeProfileBlock({this.windowKm, super.color, super.textColor});

  /// Largeur de la fenêtre « roulante », en km à venir depuis la position
  /// courante — réglée dans l'éditeur (`window_km`). `null` : le profil
  /// entier du tracé, fait/restant, comportement d'avant ce réglage. Sans
  /// effet sur la sortie enregistrée (sans tracé), qui n'a rien « à venir » à
  /// montrer — voir `AltitudeProfileCard`.
  final double? windowKm;

  static AltitudeProfileBlock parse(Map<dynamic, dynamic> raw) {
    final rawWindow = _toDouble(raw['window_km']);
    return AltitudeProfileBlock(
      windowKm: rawWindow != null && rawWindow > 0 ? rawWindow : null,
      color: DashboardBlock._colorOf(raw, 'color'),
      textColor: DashboardBlock._colorOf(raw, 'text_color'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AltitudeProfileBlock &&
      other.windowKm == windowKm &&
      other.color == color &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(windowKm, color, textColor);
}

/// Une cellule volontairement vide.
///
/// Elle existe pour que « je n'ai rien mis ici » se distingue de « le composant
/// que j'avais mis n'a pas été compris » : la première est un choix de
/// composition, la seconde un symptôme.
class EmptyBlock extends DashboardBlock {
  const EmptyBlock();

  @override
  bool operator ==(Object other) => other is EmptyBlock;

  @override
  int get hashCode => 0;
}
