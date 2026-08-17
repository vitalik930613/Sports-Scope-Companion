import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../navigation/navigation_target.dart';
import '../recording/gps_fix.dart';

/// Un pas de la prévision : précipitations (mm) sur un quart d'heure, à
/// l'heure UTC [time].
class PrecipitationStep {
  const PrecipitationStep({required this.time, required this.precipitation});

  final DateTime time;
  final double precipitation;
}

/// La prévision renvoyée par notre proxy (`/api/precipitation_forecast`, voir
/// `PrecipitationForecastController` côté site) : les pas à venir, dans
/// l'ordre chronologique en partant de maintenant.
class PrecipitationForecast {
  const PrecipitationForecast({required this.steps});

  final List<PrecipitationStep> steps;
}

/// Récupère la prévision de précipitations à 15 minutes pour une position —
/// mêmes conventions que [RainviewerClient] (`rainviewer_client.dart`) : proxy
/// Rails public, `dart:io` plutôt que le bridge WebView (données publiques,
/// pas de compte), une panne garde la dernière prévision connue plutôt que de
/// la faire disparaître.
///
/// Contrairement au catalogue RainViewer (global, un seul relevé pour tout le
/// monde), la prévision dépend de la position : un nouveau relevé n'est
/// déclenché que si la position a assez bougé ([_moveThresholdM]) ou que la
/// dernière prévision date de trop longtemps ([_freshness]) — pas à chaque fix
/// GPS, qui arrivent bien plus souvent que la donnée ne change (Open-Meteo ne
/// republie ses prévisions minutely_15 que toutes les ~15 min).
class PrecipitationForecastClient {
  PrecipitationForecastClient({
    this.baseUrl = sportsScopeBaseUrl,
    Future<String?> Function(Uri)? fetch,
  }) : _fetch = fetch ?? _fetchOverHttp;

  final String baseUrl;
  final Future<String?> Function(Uri) _fetch;

  static const _freshness = Duration(minutes: 5);
  static const _moveThresholdM = 2000;

  PrecipitationForecast? _cached;
  DateTime? _cachedAt;
  double? _cachedLat;
  double? _cachedLng;

  /// La prévision courante pour ([lat], [lng]) — relevée si le dernier appel
  /// date de trop longtemps ou si la position a trop bougé depuis, sinon la
  /// dernière connue. `null` seulement si aucun relevé n'a jamais réussi.
  Future<PrecipitationForecast?> forecastFor(double lat, double lng) async {
    final cachedAt = _cachedAt;
    final cachedLat = _cachedLat;
    final cachedLng = _cachedLng;
    final stale = cachedAt == null || DateTime.now().difference(cachedAt) >= _freshness;
    final moved = cachedLat == null ||
        cachedLng == null ||
        GpsFix.haversineM(cachedLat, cachedLng, lat, lng) >= _moveThresholdM;
    if (!stale && !moved) return _cached;

    try {
      final uri = Uri.parse('$baseUrl/api/precipitation_forecast').replace(queryParameters: {
        'lat': lat.toStringAsFixed(4),
        'lng': lng.toStringAsFixed(4),
      });
      final body = await _fetch(uri);
      if (body == null) return _cached;

      final parsed = _parse(body);
      if (parsed == null) return _cached;

      _cached = parsed;
      _cachedAt = DateTime.now();
      _cachedLat = lat;
      _cachedLng = lng;
      return _cached;
    } catch (e) {
      return _cached;
    }
  }

  static PrecipitationForecast? _parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      return null;
    }
    if (json is! Map) return null;

    final raw = json['steps'];
    if (raw is! List) return null;

    final steps = <PrecipitationStep>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final time = entry['time'];
      final precipitation = entry['precipitation'];
      if (time is! String || precipitation is! num) continue;

      final parsedTime = DateTime.tryParse(time);
      if (parsedTime == null) continue;

      steps.add(PrecipitationStep(time: parsedTime, precipitation: precipitation.toDouble()));
    }
    if (steps.isEmpty) return null;

    return PrecipitationForecast(steps: steps);
  }

  static Future<String?> _fetchOverHttp(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return await response.transform(const Utf8Decoder()).join();
    } finally {
      client.close(force: true);
    }
  }
}
