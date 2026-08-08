/// Mises en forme partagées par les écrans.
///
/// Écrites à la main plutôt que via `intl` : l'appli est en français, ses
/// unités sont métriques, et tirer une bibliothèque de localisation pour trois
/// chaînes ferait grossir l'APK sans rien apporter.
library;

/// `1:12:34` au-delà d'une heure, `12:34` en dessous. Format d'un compteur de
/// vélo : la seconde est visible, l'heure n'encombre que si elle existe.
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds.abs();
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// `4,20 km`, jamais en mètres. Pour les mesures de distance du tableau de
/// bord (distance parcourue, distance restante) : une case ne doit pas
/// changer d'unité en cours de route, contrairement à [formatDistance] qui
/// bascule sous 100 m pour un départ ou une arrivée toute proche.
String formatDistanceKm(double metres) {
  final km = metres / 1000;
  final decimals = km >= 100 ? 1 : 2;
  return '${km.toStringAsFixed(decimals).replaceAll('.', ',')} km';
}

/// `04:12`, heures toujours écrites. Pour les mesures de temps du tableau de
/// bord (durée, temps en mouvement, temps restant) : leur largeur ne doit pas
/// sauter d'un chiffre au passage de la première heure, ce que
/// [formatDuration] ferait en ajoutant les heures d'un coup.
String formatDurationHm(Duration duration) {
  final seconds = duration.inSeconds.abs();
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final hh = hours.toString().padLeft(2, '0');
  final mm = minutes.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// `04:12:07`, heures et secondes toujours écrites. Variante de
/// [formatDurationHm] pour les mesures de durée du tableau de bord dont le
/// profil demande la seconde plutôt que la minute.
String formatDurationHms(Duration duration) {
  final seconds = duration.inSeconds.abs();
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final hh = hours.toString().padLeft(2, '0');
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

/// Distance en kilomètres, virgule française. En dessous de 100 m on reste en
/// mètres : « 0,04 km » ne veut rien dire à l'échelle d'un départ.
String formatDistance(double metres) {
  if (metres < 100) return '${metres.round()} m';
  final km = metres / 1000;
  final decimals = km >= 100 ? 1 : 2;
  return '${km.toStringAsFixed(decimals).replaceAll('.', ',')} km';
}

/// `28/07/2026 · 14:03`, en heure locale.
String formatDateTime(DateTime at) {
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} · '
      '${two(local.hour)}:${two(local.minute)}';
}
