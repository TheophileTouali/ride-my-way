import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../themes/app_theme.dart';
import 'package:ride_my_way/providers/driver_provider.dart'; // et non user_provider

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<DriverProvider>(context).user;


    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.go('/home'),
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: user?.photoUrl != null
                          ? NetworkImage(user!.photoUrl!)
                          : const AssetImage('assets/images/user_placeholder.png') as ImageProvider,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.fullName ?? "Nom du conducteur",
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(user?.email ?? "", style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.green.withOpacity(0.12),
                        border: Border.all(color: Colors.greenAccent),
                      ),
                      child: const Text(
                        "✅ Profil vérifié",
                        style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 36),

                _sectionCard(title: "Informations personnelles", children: [
                  _infoRow("Adresse", user?.address ?? "-"),
                  _infoRow("Date de naissance", user?.birthdate ?? "-"),
                  _infoRow("Téléphone", user?.phone ?? "-"),
                ]),

                const SizedBox(height: 24),

                _sectionCard(title: "Informations véhicule", children: [
                  _infoRow("Marque", user?.vehicleBrand ?? "-"),
                  _infoRow("Modèle", user?.vehicleModel ?? "-"),
                  _infoRow("Année", user?.vehicleYear ?? "-"),
                ]),

                const SizedBox(height: 24),

                _sectionCard(title: "Documents", children: [
                  _infoRow("Carte d'identité", user?.idCardUrl != null ? "Ajoutée" : "Manquante"),
                  _infoRow("Photo véhicule", user?.vehiclePhotoUrl != null ? "Ajoutée" : "Manquante"),
                ]),

                const SizedBox(height: 28),

                const Divider(color: Colors.white12, thickness: 0.6, height: 32),

                _sectionCard(title: "Actions", children: [
                  _actionRow(Icons.lock_reset_rounded, "Modifier le mot de passe", () {
                    context.go('/reset-password');
                  }),
                  _actionRow(Icons.logout_rounded, "Se déconnecter", () {
                    Provider.of<DriverProvider>(context, listen: false).logout();
                    context.go('/login');
                  }, color: Colors.redAccent),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade800),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[300], fontSize: 15),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(IconData icon, String text, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.gold),
      title: Text(
        text,
        style: TextStyle(color: color ?? AppColors.gold, fontSize: 15),
      ),
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}
