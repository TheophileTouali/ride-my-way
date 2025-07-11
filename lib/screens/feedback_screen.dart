import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class FeedbackScreen extends StatefulWidget {
  final String reservationId;
  const FeedbackScreen({super.key, required this.reservationId});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> with SingleTickerProviderStateMixin {
  double _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
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

      if (resSnap.exists) {
        _reservationData = resSnap.data();
        final driverId = _reservationData!['driverId'];
        if (driverId != null) {
          final driverSnap = await FirebaseFirestore.instance.collection('drivers').doc(driverId).get();
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
    if (_rating == 0 || _reservationData == null || _driverData == null) return;

    setState(() => _isSubmitting = true);

    final feedbackData = {
      'reservationId': widget.reservationId,
      'driverId': _reservationData!['driverId'],
      'passengerId': _reservationData!['userId'],
      'rating': _rating,
      'comment': _commentController.text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance.collection('feedbacks').add(feedbackData);

    if (context.mounted) context.go('/home');
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
    final timestamp = _reservationData!['departureTime'];
    final date = timestamp is Timestamp
        ? DateFormat.yMMMMd('fr_FR').add_Hm().format(timestamp.toDate())
        : 'Date inconnue';

    final driverName = "${_driverData!['firstName'] ?? ''} ${_driverData!['lastName'] ?? ''}";
    final driverPhoto = _driverData!['photoUrl'];

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text("Noter le chauffeur",
            style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 20)),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Text("Trajet effectué",
                  style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 24),
              _infoRow("Départ", from),
              _infoRow("Arrivée", to),
              _infoRow("Date", date),
              _infoRow("Montant", "${price.toStringAsFixed(2)} €"),
              const SizedBox(height: 30),
              _buildDriverCard(driverName, driverPhoto),
              const SizedBox(height: 36),
              const Text("Attribuez une note :", style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 12),
              Center(
                child: RatingBar.builder(
                  initialRating: 0,
                  minRating: 1,
                  allowHalfRating: false,
                  itemCount: 5,
                  unratedColor: Colors.white24,
                  itemPadding: const EdgeInsets.symmetric(horizontal: 6.0),
                  itemBuilder: (context, _) => const Icon(Icons.star, size: 30, color: AppColors.gold),
                  onRatingUpdate: (rating) => setState(() => _rating = rating),
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _commentController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Laisser un commentaire (optionnel)",
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.15),
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
                icon: const Icon(Icons.send, color: Colors.black),
                label: Text(
                  _isSubmitting ? "Envoi..." : "Envoyer la note",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              "$label :",
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(String name, String? photoUrl) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: photoUrl != null
                ? NetworkImage(photoUrl)
                : const AssetImage('assets/images/avatar_placeholder.png') as ImageProvider,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text("Votre chauffeur", style: TextStyle(color: Colors.white60)),
            ],
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _controller.dispose();
    super.dispose();
  }
}
