import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherInfo {
  final String city;
  final String condition;
  final String iconUrl;
  final double temperature;
  final int humidity;
  final double windSpeed;

  WeatherInfo({
    required this.city,
    required this.condition,
    required this.iconUrl,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      city: json['location']['name'],
      condition: json['current']['condition']['text'],
      iconUrl: 'https:${json['current']['condition']['icon']}',
      temperature: json['current']['temp_c'].toDouble(),
      humidity: json['current']['humidity'],
      windSpeed: json['current']['wind_kph'].toDouble(),
    );
  }
}


Future<WeatherInfo> fetchWeather(double lat, double lon) async {
  const apiKey = 'dcc6eeb47e4b4531a5452432250607';
  final url = 'https://api.weatherapi.com/v1/current.json?key=$apiKey&q=$lat,$lon&lang=fr';

  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final data = json.decode(utf8.decode(response.bodyBytes));
    return WeatherInfo.fromJson(data);
  } else {
    throw Exception('Erreur météo : ${response.statusCode}');
  }
}



