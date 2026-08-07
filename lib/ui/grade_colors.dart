import 'package:flutter/material.dart';

/// Les tranches de pente d'un col, telles que la carte les colore déjà (voir
/// `GRADE_BUCKETS` dans `app/javascript/routeHelpers.ts` côté site — mêmes
/// seuils, mêmes couleurs, à tenir manuellement synchronisés : un site qui
/// change ses tranches sans que l'appli suive dessinerait un col dont les
/// couleurs ne correspondent plus à celles de la carte web).
const _gradeBuckets = <(double max, Color color)>[
  (-8, Color(0xFF1E3A8A)),
  (-3, Color(0xFF3B82F6)),
  (3, Color(0xFF22C55E)),
  (6, Color(0xFFEAB308)),
  (10, Color(0xFFF97316)),
  (15, Color(0xFFDC2626)),
  (double.infinity, Color(0xFF7F1D1D)),
];

/// La couleur d'un segment de profil, ou de l'étiquette de pente instantanée
/// du bandeau — mêmes tranches, un seul appelant côté web (`colorForGrade`).
Color gradeColorOf(double grade) {
  for (final (max, color) in _gradeBuckets) {
    if (grade < max) return color;
  }
  return _gradeBuckets.last.$2;
}
