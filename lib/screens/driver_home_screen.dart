// lib/screens/driver_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../providers/driver_provider.dart';
import 'package:animate_do/animate_do.dart';

class Testimonial {
  final String passengerName;
  final String avatarUrl;
  final double rating;
  final String comment;

  Testimonial({
    required this.passengerName,
    required this.avatarUrl,
    required this.rating,
    required this.comment,
  });
}

Future<List<Testimonial>> fetchDriverTestimonials() async {
  await Future.delayed(const Duration(milliseconds: 600));
  return [
    Testimonial(
      passengerName: "Alice Dupont",
      avatarUrl: "https://randomuser.me/api/portraits/women/1.jpg",
      rating: 4.8,
      comment: "Très ponctuel et agréable !",
    ),
    Testimonial(
      passengerName: "Karim B.",
      avatarUrl: "https://randomuser.me/api/portraits/men/3.jpg",
      rating: 5.0,
      comment: "Un excellent trajet, merci 😊",
    ),
    Testimonial(
      passengerName: "Sophie L.",
      avatarUrl: "https://randomuser.me/api/portraits/women/6.jpg",
      rating: 4.5,
      comment: "Conduite fluide et conversation sympa.",
    ),
  ];
}


class Trip {
  final String departure;
  final String destination;
  final DateTime date;
  final String status;
  final double price;

  Trip({
    required this.departure,
    required this.destination,
    required this.date,
    required this.status,
    required this.price,
  });
}

Future<List<Trip>> fetchDriverTrips() async {
  await Future.delayed(const Duration(milliseconds: 800));
  return [
    Trip(departure: "Paris", destination: "Versailles", date: DateTime.now().add(const Duration(days: 1)), status: 'à venir', price: 25.0),
    Trip(departure: "Paris", destination: "Lyon", date: DateTime.now().add(const Duration(days: 3)), status: 'à venir', price: 120.0),
    Trip(departure: "Orly", destination: "Paris", date: DateTime.now().subtract(const Duration(days: 1)), status: 'effectué', price: 35.0),
    Trip(departure: "Paris", destination: "Roissy Charles de Gaulle", date: DateTime.now().subtract(const Duration(days: 3)), status: 'effectué', price: 45.0),
    Trip(departure: "Paris", destination: "Disneyland", date: DateTime.now().subtract(const Duration(days: 6)), status: 'annulé', price: 60.0),
    Trip(departure: "La Défense", destination: "Paris", date: DateTime.now().subtract(const Duration(days: 2)), status: 'annulé', price: 18.0),
  ];
}


class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<DriverProvider>(context).user;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        title: const Text(
          'Accueil Conducteur',
          style: TextStyle(
            color: AppColors.gold,
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.gold),
            onPressed: () {
              Provider.of<DriverProvider>(context, listen: false).logout();
              context.go('/login-driver');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Text(
                "Bienvenue ${user?.firstName ?? 'conducteur'} 👋",
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                ),
                ),
                Row(
                children: const [
                    Icon(Icons.star, color: Colors.amber, size: 20),
                    SizedBox(width: 4),
                    Text("4.8", style: TextStyle(color: Colors.white70)),
                ],
                ),
            ],
            ),

            const SizedBox(height: 32),
            _buildWeatherCard(),
            const SizedBox(height: 24),
            _buildStatsSection(),
            const SizedBox(height: 24),
            _buildRevenueChart(),
            const SizedBox(height: 24),
                DefaultTabController(
                length: 3,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    const TabBar(
                        labelColor: AppColors.gold,
                        unselectedLabelColor: Colors.white54,
                        indicatorColor: AppColors.gold,
                        tabs: [
                        Tab(text: "À venir"),
                        Tab(text: "Effectués"),
                        Tab(text: "Annulés"),
                        ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                        height: 240,
                        child: FutureBuilder<List<Trip>>(
                        future: fetchDriverTrips(),
                        builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                            }
                            final trips = snapshot.data!;
                            return TabBarView(
                            children: ['à venir', 'effectué', 'annulé'].map((status) {
                                final filtered = trips.where((t) => t.status == status).toList();
                                if (filtered.isEmpty) {
                                return Center(child: Text("Aucun trajet $status.", style: const TextStyle(color: Colors.white54)));
                                }
                                return ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) => _tripCard(filtered[i]),
                                );
                            }).toList(),
                            );
                        },
                        ),
                    ),
                    ],
                ),
                ),

                const SizedBox(height: 24),
                FutureBuilder<List<Testimonial>>(
                future: fetchDriverTestimonials(),
                builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                    }
                    final testimonials = snapshot.data!;
                    return _infoCard(
                    title: "Avis récents 🗣️",
                    child: Column(
                        children: testimonials.map((t) => _testimonialCard(t)).toList(),
                    ),
                    );
                },
                ),


            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go('/driver-profile'),
              icon: const Icon(Icons.person, color: AppColors.black),
              label: const Text("Voir mon profil"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.black,
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

        Widget _testimonialCard(Testimonial t) {
        return FadeInUp(
            duration: const Duration(milliseconds: 400),
            child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade800),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(t.avatarUrl),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                        t.passengerName,
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                        ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                        children: List.generate(
                            5,
                            (i) => Icon(
                            i < t.rating.floor()
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 16,
                            color: Colors.amber,
                            ),
                        ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                        t.comment,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontStyle: FontStyle.italic,
                        ),
                        ),
                    ],
                    ),
                ),
                ],
            ),
            ),
        );
        }


    Widget _buildWeatherCard() {
    return FutureBuilder<WeatherInfo>(
        future: fetchWeather(),
        builder: (context, snapshot) {
        if (!snapshot.hasData) {
            return _loadingCard("Chargement météo...");
        }
        final weather = snapshot.data!;
        return _infoCard(
            title: "Météo actuelle",
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Bloc gauche (icône + ville + température)
                Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                    children: [
                    const Icon(Icons.wb_sunny_rounded, color: Colors.amber, size: 38),
                    const SizedBox(height: 8),
                    const Text("Paris", style: TextStyle(color: Colors.white60, fontSize: 14)),
                    Text(
                        "${weather.temperature}°C",
                        style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                        ),
                    ),
                    ],
                ),
                ),

                const SizedBox(width: 24),

                // Bloc droit (détails)
                Expanded(
                child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Column(
                    children: [
                        _weatherDetailRow("Conditions", weather.condition),
                        const SizedBox(height: 6),
                        _weatherDetailRow("Vent", "${weather.windDirection} – ${weather.windSpeed} km/h"),
                        const SizedBox(height: 6),
                        _weatherDetailRow("Humidité", "${weather.humidity} %"),
                        const SizedBox(height: 6),
                        _weatherDetailRow("Ressenti", "${weather.feelsLike}°C"),
                    ],
                    ),
                ),
                ),
            ],
            ),
        );
        },
    );
    }

    Widget _weatherDetailRow(String label, String value) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
        Text(
            "$label :",
            style: const TextStyle(
            color: Colors.white60,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            ),
        ),
        Text(
            value,
            style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            ),
        ),
        ],
    );
    }


  Widget _buildStatsSection() {
    return FutureBuilder<DriverStats>(
      future: fetchDriverStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _loadingCard("Chargement stats...");
        final stats = snapshot.data!;
        return _infoCard(
          title: "Mes statistiques",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statRow("Trajets", "${stats.nbTrajets}"),
              _statRow("Kilomètres", "${stats.totalKm} km"),
              _statRow("Note moyenne", "${stats.note} ⭐"),
            ],
          ),
        );
      },
    );
  }

    Widget _tripCard(Trip trip) {
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text("${trip.departure} ➜ ${trip.destination}", style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("Date : ${trip.date.toLocal().toString().split(' ')[0]}", style: const TextStyle(color: Colors.white70)),
            Text("Tarif : ${trip.price.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white70)),
        ],
        ),
    );
    }

  Widget _buildRevenueChart() {
    return _infoCard(
      title: "Mes revenus (mois) 💸",
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, _) {
                    final months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin'];
                    return Text(months[value.toInt() % 6], style: const TextStyle(color: Colors.white70, fontSize: 10));
                  },
                ),
              ),
            ),
            barGroups: List.generate(6, (index) {
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: [320, 450, 270, 620, 500, 710][index].toDouble(),
                    width: 18,
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _infoCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _loadingCard(String title) {
    return _infoCard(
      title: title,
      child: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[300])),
          Text(value, style: _valueTextStyle()),
        ],
      ),
    );
  }

  TextStyle _valueTextStyle() {
    return const TextStyle(
      color: AppColors.gold,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
  }
}

// Mocked data classes and fetchers

class DriverStats {
  final int nbTrajets;
  final int totalKm;
  final double note;

  DriverStats({required this.nbTrajets, required this.totalKm, required this.note});
}

Future<DriverStats> fetchDriverStats() async {
  await Future.delayed(const Duration(milliseconds: 800));
  return DriverStats(nbTrajets: 14, totalKm: 320, note: 4.8);
}

class WeatherInfo {
  final int temperature;
  final String iconCode;

  final String condition;
  final String windDirection;
  final double windSpeed;
  final int humidity;
  final double feelsLike;

  WeatherInfo({
    required this.temperature,
    required this.iconCode,
    required this.condition,
    required this.windDirection,
    required this.windSpeed,
    required this.humidity,
    required this.feelsLike,
  });
}


Future<WeatherInfo> fetchWeather() async {
  await Future.delayed(const Duration(milliseconds: 500));
  return WeatherInfo(
    temperature: 26,
    iconCode: '01d',
    condition: 'Ensoleillé',
    windDirection: 'Nord-Ouest',
    windSpeed: 12.0,
    humidity: 60,
    feelsLike: 28.0,
  );
}

