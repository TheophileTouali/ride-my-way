import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class WeatherCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const WeatherCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final temp = data['main']['temp'].round();
    final city = data['name'];
    final desc = data['weather'][0]['description'];
    final icon = data['weather'][0]['icon'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Image.network(
            'http://openweathermap.org/img/wn/$icon@2x.png',
            width: 60,
            height: 60,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$city, $temp°C",
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
