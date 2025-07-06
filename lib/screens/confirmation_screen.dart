import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class ConfirmationScreen extends StatefulWidget {
  final String from;
  final String to;
  final String vehicle;
  final double price;
  final double distance;

  const ConfirmationScreen({
    super.key,
    required this.from,
    required this.to,
    required this.vehicle,
    required this.price,
    required this.distance,
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  DateTime? _selectedDateTime;
  bool _isNowSelected = true;

  String formatDateTime(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} à ${dt.hour}h${dt.minute.toString().padLeft(2, '0')}";
  }

    void _selectAnotherTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF0D0D0D),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.gold,
            ),
          ),
        ),
        child: child!,
      ),

    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0D0D0D),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
              ),
            ),
          ),
          child: child!,
        ),

      );

      if (pickedTime != null) {
        final selected = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() {
          _selectedDateTime = selected;
          _isNowSelected = false;
        });
      }
    }
  }


    Future<void> _confirmTrip() async {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Utilisateur non connecté")),
        );
        return;
      }

      try {
        final departureTime = _isNowSelected
            ? DateTime.now().add(const Duration(minutes: 3))
            : _selectedDateTime!;

        final reservationData = {
          'from': widget.from,
          'to': widget.to,
          'vehicle': widget.vehicle,
          'price': widget.price,
          'distance': widget.distance,
          'userId': user.uid,
          'timestamp': Timestamp.fromDate(departureTime),
          'status': 'En attente',
          'createdAt': FieldValue.serverTimestamp(),
          'expiredSearch': false,
        };

        final docRef = await FirebaseFirestore.instance.collection('reservations').add(reservationData);

        // ✅ Redirection vers la page de recherche
        context.go('/searching?reservationId=${docRef.id}');
      } catch (e) {
        print("Erreur Firestore: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de la confirmation.")),
        );
      }
    }




  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            "$label : ",
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'PlayfairDisplay',
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowBlock() {
    if (!_isNowSelected) return const SizedBox.shrink();

    final nowPlus3 = DateTime.now().add(const Duration(minutes: 3));
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Text(
            "Vous partez maintenant : ",
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'PlayfairDisplay',
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              formatDateTime(nowPlus3),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Planifier votre départ",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    builder: (context, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppColors.gold,
                        onPrimary: Colors.black,
                        surface: Color(0xFF1A1A1A),
                        onSurface: Colors.white,
                      ),
                      dialogBackgroundColor: const Color(0xFF0D0D0D),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.gold,
                        ),
                      ),
                    ),
                    child: child!,
                  ),

                  );

                  if (pickedDate != null) {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppColors.gold,
                              onPrimary: Colors.black,
                              surface: Color(0xFF1A1A1A),
                              onSurface: Colors.white,
                            ),
                            dialogBackgroundColor: const Color(0xFF0D0D0D),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.gold,
                              ),
                            ),
                          ),
                          child: child!,
                        ),

                    );

                    if (pickedTime != null) {
                      final selected = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );

                      setState(() {
                        _selectedDateTime = selected;
                        _isNowSelected = false;
                      });
                    }
                  }
                },
                child: const Text(
                  "Planifier un autre moment",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 16,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.calendar_today, color: AppColors.gold),
            ],
          ),
        ),
      ],
    );
  }

@override
Widget build(BuildContext context) {
  final nowPlus3 = DateTime.now().add(const Duration(minutes: 3));
  final departureTime = _isNowSelected ? nowPlus3 : _selectedDateTime!;

  return Scaffold(
    backgroundColor: const Color(0xFF0D0D0D),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.gold, size: 20),
        tooltip: 'Retour',
        onPressed: () {
          if (context.canPop()) {
            context.pop(); // revient à la page précédente
          } else {
            context.go('/results'); // fallback vers l’accueil si aucun historique
          }
        },
      ),
      title: const Text(
        "Confirmation de votre trajet sur mesure",
        style: TextStyle(
          fontFamily: 'PlayfairDisplay',
          color: AppColors.gold,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
    ),

    body: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: AppColors.gold, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                    ).createShader(bounds);
                  },
                  child: const Text(
                    "Résumé de votre trajet, conçu pour l'excellence",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PlayfairDisplay',
                      color: Colors.white, // requis pour shader
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Résumé du trajet
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoLine("Départ", widget.from),
                const SizedBox(height: 10),
                _buildInfoLine("Arrivée", widget.to),
                const SizedBox(height: 10),
                _buildInfoLine("Véhicule", widget.vehicle),
                const SizedBox(height: 10),
                _buildInfoLine("Distance", "${widget.distance.toStringAsFixed(1)} km"),
                const SizedBox(height: 10),
                _buildInfoLine("Prix", "${widget.price.toStringAsFixed(2)} €"),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Départ immédiat
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled_rounded, color: AppColors.gold, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Vous partez maintenant : ${_formatTimestamp(Timestamp.fromDate(departureTime))}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),


          const SizedBox(height: 20),

          // Planification
const SizedBox(height: 20),
          const Text("Planifier votre départ", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay')),
          const SizedBox(height: 6),
          const Text("Vous préférez plus tard ? Choisissez le moment idéal.", style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'PlayfairDisplay', fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withOpacity(0.2)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), offset: const Offset(0, 2), blurRadius: 6)],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              leading: const Icon(Icons.calendar_today_rounded, color: AppColors.gold),
              title: const Text("Planifier un autre moment", style: TextStyle(color: AppColors.gold, fontSize: 16, fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w600)),
              onTap: _selectAnotherTime,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.transparent,
            ),
          ),

          const Spacer(),

          // Bouton confirmation
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmTrip,
              icon: const Icon(Icons.check_circle, color: Colors.black),
              label: const Text(
                "Confirmer ce trajet",
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}



  Widget _buildInfoLine(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        "$label : ",
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ),
    ],
  );
}

String _formatTimestamp(Timestamp timestamp) {
  final dateTime = timestamp.toDate();
  return "${dateTime.day}/${dateTime.month}/${dateTime.year} à ${dateTime.hour}h${dateTime.minute.toString().padLeft(2, '0')}";
}

}
