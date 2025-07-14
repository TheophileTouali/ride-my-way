import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class PassengerFeedbackScreen extends StatefulWidget {
  final String reservationId;
  const PassengerFeedbackScreen({super.key, required this.reservationId});

  @override
  State<PassengerFeedbackScreen> createState() => _PassengerFeedbackScreenState();
}

class _PassengerFeedbackScreenState extends State<PassengerFeedbackScreen>
    with SingleTickerProviderStateMixin {
  double _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _recommend = true;

  Map<String, dynamic>? _reservationData;
  Map<String, dynamic>? _driverData;

  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _loadReservationData();
  }

  Future<void> _loadReservationData() async {
    try {
      final resSnap = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .get();

      if (_driverData == null) {
        _driverData = {
          'firstName': 'Conducteur',
          'lastName': '',
          'photoUrl': null,
        };
      }

      if (resSnap.exists) {
        _reservationData = resSnap.data();
        final driverId = _reservationData!['driverId'];
        if (driverId != null) {
          final driverSnap =
              await FirebaseFirestore.instance.collection('drivers').doc(driverId).get();
          if (driverSnap.exists) {
            _driverData = driverSnap.data();
          }
        }
        setState(() {});
        _controller.forward();
      }
    } catch (e) {
      debugPrint("Erreur chargement : $e");
    }
  }

  Future<void> _submitFeedback() async {
    if (_isSubmitting || _rating == 0 || _reservationData == null || _driverData == null) return;

    setState(() => _isSubmitting = true);

    final feedbackData = {
      'reservationId': widget.reservationId,
      'driverId': _reservationData!['driverId'],
      'passengerId': _reservationData!['userId'],
      'fromDriver': false,
      'rating': _rating,
      'comment': _commentController.text.trim(),
      'recommend': _recommend,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance.collection('feedbacks').add(feedbackData);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: AppColors.gold),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Merci pour votre évaluation !",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.black.withOpacity(0.95),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.gold, width: 1),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          duration: const Duration(seconds: 3),
          elevation: 12,
        ),
      );

      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_reservationData == null || _driverData == null) {
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    final from = _reservationData!['from'] ?? 'Départ inconnu';
    final to = _reservationData!['to'] ?? 'Arrivée inconnue';
    final price = (_reservationData!['price'] ?? 0).toDouble();
    final timestamp = _reservationData!['timestamp'];
    final date = timestamp is Timestamp
        ? DateFormat.yMMMMd('fr_FR').add_Hm().format(timestamp.toDate())
        : 'Date inconnue';

    final driverName =
        "${_driverData!['firstName'] ?? ''} ${_driverData!['lastName'] ?? ''}".trim();
    final driverPhoto = _driverData!['photoUrl'];

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "🚗 Noter le chauffeur",
          style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Text("✨ Trajet terminé",
                  style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 16),
              Text(
                "Merci pour ce trajet.\nVous pouvez maintenant évaluer votre chauffeur. Votre retour améliore notre communauté.",
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textScaleFactor: 1.0,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "— L'équipe Ride My Way",
                  style: TextStyle(
                    color: AppColors.gold.withOpacity(0.9),
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.gold, thickness: 1.2),
              const SizedBox(height: 8),
              _infoRow(Icons.location_pin, "Départ", from),
              _infoRow(Icons.flag_rounded, "Arrivée", to),
              _infoRow(Icons.calendar_today_rounded, "Date", date),
              _infoRow(Icons.euro_rounded, "Montant", "${price.toStringAsFixed(2)} €"),
              const SizedBox(height: 30),
              _buildUserCard(driverName, driverPhoto),
              const SizedBox(height: 36),
              const Text(
                "🌟 Attribuez une note",
                style: TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w500),
                textScaleFactor: 1.0,
              ),
              const SizedBox(height: 14),
              Center(
                child: RatingBar.builder(
                  initialRating: 0,
                  minRating: 1,
                  allowHalfRating: false,
                  itemCount: 5,
                  unratedColor: Colors.white24,
                  itemPadding: const EdgeInsets.symmetric(horizontal: 6.0),
                  itemBuilder: (context, _) =>
                      const Icon(Icons.star_rounded, size: 34, color: AppColors.gold),
                  onRatingUpdate: (rating) => setState(() => _rating = rating),
                ),
              ),
              const SizedBox(height: 30),
              _recommendSwitch(),
              const SizedBox(height: 20),
              TextField(
                controller: _commentController,
                maxLines: 4,
                maxLength: 250,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "💬 Laisser un commentaire (optionnel)",
                  hintStyle: const TextStyle(color: Colors.white54),
                  counterStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.gold),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _rating == 0 || _isSubmitting ? null : _submitFeedback,
                icon: const Icon(Icons.rocket_launch, color: Colors.black),
                label: Text(
                  _isSubmitting ? "Envoi..." : "Envoyer la note",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold, size: 22),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w600)),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white),
                  textScaleFactor: 1.0)),
        ],
      ),
    );
  }

  Widget _buildUserCard(String name, String? photoUrl) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: photoUrl != null
                ? NetworkImage(photoUrl)
                : const AssetImage('assets/images/avatar_placeholder.png') as ImageProvider,
            onBackgroundImageError: (_, __) {
              debugPrint("🧨 Erreur chargement image chauffeur : $photoUrl");
            },
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                  textScaleFactor: 1.0),
              const SizedBox(height: 4),
              const Text("Votre chauffeur", style: TextStyle(color: Colors.white60)),
            ],
          )
        ],
      ),
    );
  }

  Widget _recommendSwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const Icon(Icons.thumb_up_alt_rounded, color: AppColors.gold),
        const SizedBox(width: 12),
        const Text(
          "Recommander ce chauffeur",
          style: TextStyle(color: Colors.white70, fontSize: 16),
          textScaleFactor: 1.0,
        ),
        const Spacer(),
        Switch(
          value: _recommend,
          activeColor: AppColors.gold,
          onChanged: (value) => setState(() => _recommend = value),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _controller.dispose();
    super.dispose();
  }
}
