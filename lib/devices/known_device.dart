import '../ble/sensor_profile.dart';

/// Un appareil déjà appairé, tel qu'on s'en souvient entre deux lancements.
///
/// On retient l'identifiant BLE, pas l'objet `BluetoothDevice` : celui-ci est
/// reconstruit à partir de [remoteId] au démarrage, sans re-scanner. Le nom et
/// les capacités sont là pour l'affichage avant même que l'appareil réponde —
/// on peut donc afficher « Ceinture cardio · hors de portée » plutôt qu'une
/// ligne muette.
class KnownDevice {
  const KnownDevice({
    required this.remoteId,
    required this.name,
    this.kinds = const {},
    this.lastConnectedAt,
    this.autoConnect = true,
  });

  /// Adresse MAC (Android) ou UUID (iOS). Stable pour un capteur donné.
  final String remoteId;

  final String name;

  /// Capacités constatées à la dernière connexion réussie.
  final Set<SensorKind> kinds;

  final DateTime? lastConnectedAt;

  /// Se reconnecter tout seul au lancement. Décoché, l'appareil reste dans la
  /// liste mais n'est plus sollicité — utile pour un capteur prêté ou un vélo
  /// qu'on n'utilise pas aujourd'hui.
  final bool autoConnect;

  KnownDevice copyWith({
    String? name,
    Set<SensorKind>? kinds,
    DateTime? lastConnectedAt,
    bool? autoConnect,
  }) {
    return KnownDevice(
      remoteId: remoteId,
      name: name ?? this.name,
      kinds: kinds ?? this.kinds,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }

  Map<String, dynamic> toJson() => {
        'remoteId': remoteId,
        'name': name,
        'kinds': [for (final kind in kinds) kind.name],
        'lastConnectedAt': lastConnectedAt?.toIso8601String(),
        'autoConnect': autoConnect,
      };

  /// Renvoie `null` sur une entrée inexploitable plutôt que de lever : un
  /// fichier à moitié écrit ne doit pas empêcher l'appli de démarrer, et perdre
  /// un appareil connu se rattrape en un scan.
  static KnownDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    final remoteId = json['remoteId'];
    if (remoteId is! String || remoteId.isEmpty) return null;

    final rawKinds = json['kinds'];
    final kinds = <SensorKind>{};
    if (rawKinds is List) {
      for (final raw in rawKinds) {
        // Un profil retiré d'une version à l'autre laisse un nom inconnu : on
        // l'ignore au lieu de rejeter tout l'appareil.
        for (final kind in SensorKind.values) {
          if (kind.name == raw) kinds.add(kind);
        }
      }
    }

    final rawDate = json['lastConnectedAt'];
    return KnownDevice(
      remoteId: remoteId,
      name: json['name'] is String ? json['name'] as String : '',
      kinds: kinds,
      lastConnectedAt:
          rawDate is String ? DateTime.tryParse(rawDate) : null,
      autoConnect: json['autoConnect'] is bool ? json['autoConnect'] as bool : true,
    );
  }

  @override
  String toString() => 'KnownDevice($remoteId, $name, ${kinds.map((k) => k.name)})';
}
