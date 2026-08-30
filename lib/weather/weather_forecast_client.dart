import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../navigation/navigation_target.dart';
import '../recording/gps_fix.dart';

/// Un pas de la prévision : température (°C), vent (km/h), direction d'où
/// vient le vent ([windDirection], degrés, convention météo — 0 = du nord,
/// 90 = de l'est) et précipitations (mm) sur l'heure, à l'heure UTC [time].
class WeatherForecastStep {
  const WeatherForecastStep({
    required this.time,
    required this.temperature,
    required this.windSpeed,
    required this.precipitation,
    this.windDirection,
  });

  final DateTime time;
  final double temperature;
  final double windSpeed;
  final double precipitation;

  /// `null` pour une prévision servie par un site antérieur à ce champ — le
  /// bloc « vent » se rabat alors sur la seule vitesse absolue, sans
  /// projection sur le cap.
  final double? windDirection;
}

/// La prévision renvoyée par notre proxy (`/api/weather_forecast`, voir
/// `WeatherForecastController` côté site) : les pas à venir, dans l'ordre
/// chronologique en partant de maintenant.
class WeatherForecast {
  const WeatherForecast({required this.steps});

  final List<WeatherForecastStep> steps;
}

/// Récupère la prévision météo horaire pour une position — mêmes conventions
/// que [PrecipitationForecastClient] (`precipitation_forecast_client.dart`) :
/// proxy Rails public, `dart:io` plutôt que le bridge WebView (données
/// publiques, pas de compte), une panne garde la dernière prévision connue
/// plutôt que de la faire disparaître.
///
/// Seuils plus lâches que [PrecipitationForecastClient] : la donnée est
/// horaire (le serveur ne la republie que toutes les 15 min, voir
/// `WeatherForecastController::CACHE_TTL`) et température/vent ne varient pas
/// assez sur quelques centaines de mètres pour justifier un appel à chaque
/// déplacement.
class WeatherForecastClient {
  WeatherForecastClient({
    this.baseUrl = sportsScopeBaseUrl,
    Future<String?> Function(Uri)? fetch,
  }) : _fetch = fetch ?? _fetchOverHttp;

  final String baseUrl;
  final Future<String?> Function(Uri) _fetch;

  static const _freshness = Duration(minutes: 15);
  static const _moveThresholdM = 5000;

  WeatherForecast? _cached;
  DateTime? _cachedAt;
  double? _cachedLat;
  double? _cachedLng;

  /// La prévision courante pour ([lat], [lng]) — relevée si le dernier appel
  /// date de trop longtemps ou si la position a trop bougé depuis, sinon la
  /// dernière connue. `null` seulement si aucun relevé n'a jamais réussi.
  Future<WeatherForecast?> forecastFor(double lat, double lng) async {
    final cachedAt = _cachedAt;
    final cachedLat = _cachedLat;
    final cachedLng = _cachedLng;
    final stale = cachedAt == null || DateTime.now().difference(cachedAt) >= _freshness;
    final moved = cachedLat == null ||
        cachedLng == null ||
        GpsFix.haversineM(cachedLat, cachedLng, lat, lng) >= _moveThresholdM;
    if (!stale && !moved) return _cached;

    try {
      final uri = Uri.parse('$baseUrl/api/weather_forecast').replace(queryParameters: {
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

  static WeatherForecast? _parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (e) {
      return null;
    }
    if (json is! Map) return null;

    final raw = json['steps'];
    if (raw is! List) return null;

    final steps = <WeatherForecastStep>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final time = entry['time'];
      final temperature = entry['temperature'];
      final windSpeed = entry['wind_speed'];
      final precipitation = entry['precipitation'];
      if (time is! String || temperature is! num || windSpeed is! num || precipitation is! num) {
        continue;
      }
      final windDirection = entry['wind_direction'];

      final parsedTime = DateTime.tryParse(time);
      if (parsedTime == null) continue;

      steps.add(WeatherForecastStep(
        time: parsedTime,
        temperature: temperature.toDouble(),
        windSpeed: windSpeed.toDouble(),
        precipitation: precipitation.toDouble(),
        windDirection: windDirection is num ? windDirection.toDouble() : null,
      ));
    }
    if (steps.isEmpty) return null;

    return WeatherForecast(steps: steps);
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
