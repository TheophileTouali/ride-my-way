
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart'; 
import '../themes/app_theme.dart';
import '../providers/driver_provider.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<DriverProvider>(context).user;
    print("🧑‍🚗 Profil chargé : ${user?.photoUrl}");
    print("🚗 Photo véhicule : ${user?.vehiclePhotoUrl}");


    if (user == null) {
      Future.microtask(() => context.go('/login-driver'));
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.go('/driver-home'),
        ),
        centerTitle: true,
        title: const Text(
          "Mon Profil Conducteur",
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // BLOC 1 — Profil conducteur premium
          Animate(
            effects: [
              FadeEffect(duration: 500.ms),
              MoveEffect(begin: const Offset(0, 20), duration: 500.ms),
            ],
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.gold, AppColors.deepGold],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 42,
                      backgroundImage: user.photoUrl != null
                          ? NetworkImage(user.photoUrl!)
                          : const AssetImage('assets/images/user_placeholder.png') as ImageProvider,
                      backgroundColor: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                            fontFamily: 'PlayfairDisplay',
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _infoLine(icon: Icons.email_rounded, value: user.email, color: Colors.white70),
                        _infoLine(icon: Icons.phone_android_rounded, value: user.phone, color: AppColors.deepGold),
                        if (user.address?.isNotEmpty ?? false)
                          _infoLine(icon: Icons.location_on_rounded, value: user.address!, color: Colors.white60),
                        if (user.birthdate?.isNotEmpty ?? false)
                          _infoLine(icon: Icons.cake_outlined, value: user.birthdate!, color: Colors.white54),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: Colors.green.withOpacity(0.08),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified, size: 18, color: Colors.greenAccent),
                              SizedBox(width: 6),
                              Text(
                                'Profil vérifié',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),




              const SizedBox(height: 24),
              // BLOC 2 — Véhicule premium animé
              Animate(
                effects: [
                  FadeEffect(duration: 500.ms),
                  MoveEffect(begin: const Offset(0, 30), duration: 500.ms),
                ],
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 100,
                            height: 80,
                            child: Image.network(
                              user.vehiclePhotoUrl ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/images/vehicles_motos_premium.png',
                                  fit: BoxFit.cover,
                                );
                              },
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            (loadingProgress.expectedTotalBytes ?? 1)
                                        : null,
                                    color: AppColors.deepGold,
                                    strokeWidth: 2,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (user.vehicleBrand != null && user.vehicleBrand!.isNotEmpty)
                              Text(
                                "Votre ${user.vehicleBrand!} est prête à briller sur la route.",
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'PlayfairDisplay',
                                ),
                              ),
                            if (user.vehicleYear != null && user.vehicleYear!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(
                                  "Modèle ${user.vehicleYear!} — entre style, puissance et précision.",
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            if ((user.vehicleBrand == null || user.vehicleBrand!.isEmpty) &&
                                (user.vehicleYear == null || user.vehicleYear!.isEmpty))
                              const Text(
                                "Ajoutez votre véhicule pour mettre en valeur votre style de conduite.",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),





                const SizedBox(height: 24),

                // BLOC 3 — Documents premium
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "📄 Vos documents",
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _docLine("Permis de conduire", user.driverLicenseUrl != null),
                      const Divider(color: Colors.white10, height: 24),
                      _docLine("Carte grise", user.registrationUrl != null),
                      const Divider(color: Colors.white10, height: 24),
                      _docLine("Assurance", user.insuranceUrl != null),
                    ],
                  ),
                ),


          const SizedBox(height: 28),
          const Divider(color: Colors.white10),
          const SizedBox(height: 28),

          // BLOC 4 — Actions premium
          Text(
            "Paramètres du compte",
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
          const SizedBox(height: 16),

          Animate(
            effects: [
              FadeEffect(duration: 400.ms),
              MoveEffect(begin: const Offset(0, 20), duration: 400.ms),
            ],
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_reset, color: AppColors.deepGold),
                    title: const Text(
                      "Modifier le mot de passe",
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    onTap: () => context.go('/reset-password'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    title: const Text(
                      "Se déconnecter",
                      style: TextStyle(color: Colors.redAccent, fontSize: 15),
                    ),
                    onTap: () {
                      Provider.of<DriverProvider>(context, listen: false).logout();
                      context.go('/login-driver');
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ],
              ),
            ),
          ),

            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade800),
    );
  }

  Widget _docLine(String title, bool isAdded) {
  return Row(
    children: [
      Icon(
        isAdded ? Icons.check_circle_rounded : Icons.cancel_rounded,
        color: isAdded ? Colors.greenAccent : Colors.redAccent,
        size: 18,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: isAdded ? Colors.white70 : Colors.white38,
            fontSize: 14,
            fontWeight: isAdded ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
      Text(
        isAdded ? "Ajouté" : "Manquant",
        style: TextStyle(
          color: isAdded ? Colors.greenAccent : Colors.redAccent,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      )
    ],
  );
}


    Widget _infoLine({required IconData icon, required String value, required Color color}) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color.withOpacity(0.7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
      }


  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Map<String, String> items) {
    return Container(
      decoration: _boxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
          const SizedBox(height: 12),
          ...items.entries.map((e) => _infoRow(e.key, e.value)).toList(),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Icon(icon, color: color ?? AppColors.gold),
      title: Text(label, style: TextStyle(color: color ?? AppColors.gold, fontSize: 15)),
      onTap: onTap,
      tileColor: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
