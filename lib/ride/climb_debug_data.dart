import 'climb_profile.dart';
import 'nav_state.dart';

/// Un col synthétique, partagé par [ClimbDebugPage] (accueil) et le bouton
/// « Simuler un col » du menu de sortie : même forme des deux côtés, pour ne
/// pas juger deux profils différents selon l'endroit d'où on regarde.
///
/// Reprend la forme de `buildDebugClimb` côté site (navHelpers.ts) : 28
/// segments, une pente qui monte de 3 % en bas à 14 % au sommet, un profil
/// convexe.
ClimbProfile debugClimbProfile() {
  const n = 28;
  const lengthM = 8400.0;
  const gainM = 560.0;
  final points = <ClimbProfilePoint>[];
  for (var i = 0; i <= n; i++) {
    final f = i / n;
    points.add(
      ClimbProfilePoint(distM: f * lengthM, altM: 800 + gainM * (f * f)),
    );
  }
  final grades = <double>[
    for (var i = 0; i < n; i++) 3 + (i / n) * 11,
  ];
  return ClimbProfile(
    id: -1,
    gainM: gainM,
    lengthM: lengthM,
    avgGrade: gainM / lengthM * 100,
    category: '2',
    points: points,
    segmentGrades: grades,
  );
}

/// Le [NavClimb] scalaire correspondant à une position donnée sur
/// [debugClimbProfile] — même rôle que le `nav.climb` reçu par la page, mais
/// calculé ici plutôt que republié par un vrai col.
NavClimb debugClimbFor(ClimbProfile profile, double ratio) {
  final gainM = profile.gainM;
  return NavClimb(
    ratio: ratio,
    remainingGainM: gainM * (1 - ratio),
    grade: _gradeAt(profile, ratio),
    gainM: gainM,
    lengthM: profile.lengthM,
    category: profile.category,
  );
}

double _gradeAt(ClimbProfile profile, double ratio) {
  final grades = profile.segmentGrades;
  if (grades.isEmpty) return 0;
  final i = (ratio * grades.length).floor().clamp(0, grades.length - 1);
  return grades[i];
}
