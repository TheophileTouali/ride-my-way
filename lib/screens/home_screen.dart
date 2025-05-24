import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  int _currentPage = 0;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Provider.of<UserProvider>(context).userName;
    final greeting = _getGreeting();

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppColors.gold),
            onPressed: () => context.go('/profile'),
            tooltip: "Mon profil",
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Accueil", style: TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("$greeting 👋", style: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay')),
                Text(userEmail, style: const TextStyle(color: AppColors.gold, fontSize: 16)),
                const SizedBox(height: 24),

                _homeButton(context, Icons.search, "Chercher un trajet", '/search'),
                _homeButton(context, Icons.event_note, "Mes réservations", '/reservations'),
                _homeButton(context, Icons.favorite_border, "Mes favoris", '/favorites'),
                _homeButton(context, Icons.person, "Mon profil", '/profile'),

                const SizedBox(height: 24),

                SizedBox(
                  height: 160,
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    children: const [
                      _TripCard(
                        title: "Prochain trajet",
                        from: "Boissy st leger",
                        to: "Paris",
                        date: "24 mai à 19h30",
                      ),
                      _TripCard(
                        title: "Dernier trajet",
                        from: "Paris",
                        to: "Créteil",
                        date: "20 mai à 18h00",
                      ),
                      _TripCard(
                        title: "Voir tous mes trajets",
                        from: "",
                        to: "",
                        date: "",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) => _buildDot(index == _currentPage)),
                ),

                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.red.withOpacity(0.1),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Expanded(child: Text("Certaines informations de votre profil sont incomplètes.", style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Provider.of<UserProvider>(context, listen: false).logout();
                      context.go('/login');
                    },
                    child: const Text("Se déconnecter", style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeButton(BuildContext context, IconData icon, String label, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(color: Colors.white)),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 16 : 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.gold : Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final String title;
  final String from;
  final String to;
  final String date;

  const _TripCard({required this.title, required this.from, required this.to, required this.date});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (from.isNotEmpty && to.isNotEmpty)
              Text("$from ➜ $to", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            if (date.isNotEmpty)
              Text("Départ prévu : $date", style: const TextStyle(color: Colors.white60, fontSize: 13)),
            if (from.isEmpty && to.isEmpty)
              Center(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    foregroundColor: AppColors.gold,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("Voir tous mes trajets"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
