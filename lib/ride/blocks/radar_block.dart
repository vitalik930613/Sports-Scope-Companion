import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../radar_severity.dart';
import 'block_card.dart';

/// Le radar arrière, posé dans une page de données.
///
/// La règle qui tient tout : **`absent` n'est pas `clear`.** Pas de radar ne
/// veut pas dire route dégagée. Écrire « voie libre » sans capteur serait la
/// pire information que cet écran puisse donner, et c'est précisément l'instant
/// où on la croirait — d'où « Pas de radar », qui ne se confond avec rien.
///
/// Le bloc est **facultatif dans un profil** et le restera : les gouttières et
/// le cadre de la coquille disent déjà le radar sur toutes les pages. Celui-ci
/// sert au profil qui veut le chiffre en grand, ou qui a coupé les gouttières.
class RadarBlockView extends StatelessWidget {
  const RadarBlockView({
    super.key,
    required this.radar,
    this.mode = RadarMode.distance,
  });

  /// Nul quand le profil a coupé le radar : le bloc le dit alors, plutôt que
  /// d'attendre indéfiniment une trame qui ne viendra pas.
  final ValueListenable<RadarView>? radar;

  final RadarMode mode;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);
  static const _clear = Color(0xFF81C784);

  @override
  Widget build(BuildContext context) {
    final radar = this.radar;
    if (radar == null) {
      return const BlockCard(
        title: 'Radar',
        lines: ['Coupé par ce profil.'],
      );
    }

    return ValueListenableBuilder<RadarView>(
      valueListenable: radar,
      builder: (context, view, _) => switch (mode) {
        RadarMode.gauge => _gauge(view),
        RadarMode.distance => _distance(view),
        RadarMode.compact => _compactDistance(view),
        RadarMode.count => _count(view),
        RadarMode.icons => _icons(view),
      },
    );
  }

  /// Le texte qui remplace tout affichage quand il n'y a rien à compter :
  /// `absent` et `clear` ne se distinguent jamais d'un chiffre, sous peine de
  /// se lire « 0 » — un compte à zéro se lirait comme une route dégagée, ce
  /// qu'un radar débranché n'a pas le droit de dire.
  (String, Color)? _emptyState(RadarSeverity severity) => switch (severity) {
        RadarSeverity.clear => ('Voie libre', _clear),
        RadarSeverity.absent => ('Pas de radar', Colors.white38),
        RadarSeverity.approaching || RadarSeverity.close => null,
      };

  Widget _distance(RadarView view) {
    final (label, color) = switch (view.severity) {
      RadarSeverity.close => ('${view.nearestM} m', _close),
      RadarSeverity.approaching => ('${view.nearestM} m', _approaching),
      RadarSeverity.clear => ('Voie libre', _clear),
      RadarSeverity.absent => ('Pas de radar', Colors.white38),
    };

    return BlockSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // L'icône dit ce que la couleur dit déjà, quand il y a de quoi
          // alerter : sans voiture proche, il n'y a rien à redire au chiffre.
          if (view.isAlerting)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_car,
                  size: BlockMetrics.natural.iconSize + 2,
                  color: color,
                ),
                // Le compte n'est écrit que s'il y a de quoi compter : « ×1 »
                // sous une seule voiture ferait chercher la deuxième.
                if (view.count > 1)
                  Text(
                    ' ×${view.count}',
                    style: TextStyle(
                      color: color,
                      fontSize: BlockMetrics.natural.iconSize,
                    ),
                  ),
              ],
            ),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  /// Les mêmes mètres que [_distance], sans l'icône ni le compte au-dessus :
  /// juste le chiffre, pour la cellule trop basse pour deux lignes. Couleurs
  /// et texte de repli partagés avec [_count] et [_icons] via [_emptyState] —
  /// les trois racontent le même radar, ils ne doivent pas le raconter
  /// différemment.
  Widget _compactDistance(RadarView view) {
    final empty = _emptyState(view.severity);
    return _emptyText(
      empty ??
          (
            '${view.nearestM} m',
            view.severity == RadarSeverity.close ? _close : _approaching,
          ),
    );
  }

  /// Le compte, pour qui veut savoir combien de véhicules remontent plutôt
  /// qu'à quelle distance est le premier : une icône, et le nombre en gros à
  /// côté. Contrairement à [_distance], le compte s'écrit même à un seul
  /// véhicule — ici c'est le nombre qui est la donnée du composant, pas un
  /// rappel de l'icône.
  Widget _count(RadarView view) {
    final empty = _emptyState(view.severity);
    if (empty != null) return _emptyText(empty);

    final color = view.severity == RadarSeverity.close ? _close : _approaching;
    return BlockSurface(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car, size: 44, color: color),
          Text(
            ' ×${view.count}',
            style: TextStyle(
              color: color,
              fontSize: 44,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Une icône par véhicule suivi, sans chiffre : le compte se lit d'un coup
  /// d'œil plutôt qu'en déchiffrant un nombre. Une seule couleur pour toute la
  /// rangée, celle du véhicule le plus proche.
  Widget _icons(RadarView view) {
    final empty = _emptyState(view.severity);
    if (empty != null) return _emptyText(empty);

    final color = view.severity == RadarSeverity.close ? _close : _approaching;
    return BlockSurface(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < view.count; i++)
            Icon(Icons.directions_car, size: 40, color: color),
        ],
      ),
    );
  }

  /// Le texte partagé par [_compactDistance], [_count] et [_icons] : la même
  /// mise en forme sert au chiffre normal comme au texte de repli, pour que
  /// les trois passent de l'un à l'autre sans changer de taille ni de poids.
  Widget _emptyText((String, Color) state) {
    final (label, color) = state;
    return BlockSurface(
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 44,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }

  /// Un simple aplat de couleur, sans chiffre ni icône : ce qui se lit le
  /// plus vite du coin de l'œil, pour la case la plus petite de la grille.
  /// Mêmes couleurs que partout ailleurs sur ce bloc — orange qui approche,
  /// rouge qui est proche — plus le vert et le gris des états sans alerte,
  /// via [_emptyState].
  Widget _gauge(RadarView view) {
    final color = _emptyState(view.severity)?.$2 ??
        (view.severity == RadarSeverity.close ? _close : _approaching);

    return BlockSurface(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox.square(dimension: 64),
      ),
    );
  }
}
