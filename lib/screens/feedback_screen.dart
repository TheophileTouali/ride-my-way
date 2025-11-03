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
  State<PassengerFeedbackScreen> createState() =>
      _PassengerFeedbackScreenState();
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

  // Tags rapides (facultatifs)
  final List<String> _quickTags = const [
    "Ponctualité",
    "Conduite sûre",
    "Propreté",
    "Courtoisie",
    "Musique adaptée",
    "Itinéraire optimal"
  ];
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _loadReservationData();
  }

  Future<void> _loadReservationData() async {
    try {
      final resSnap = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .get();

      // Valeurs fallback chauffeur
      _driverData ??= {
        'firstName': 'Conducteur',
        'lastName': '',
        'photoUrl': null,
      };

      if (resSnap.exists) {
        _reservationData = resSnap.data();
        final driverId = _reservationData!['driverId'];
        if (driverId != null && (driverId as String).isNotEmpty) {
          final driverSnap = await FirebaseFirestore.instance
              .collection('drivers')
              .doc(driverId)
              .get();
          if (driverSnap.exists) _driverData = driverSnap.data();
        }
        if (mounted) {
          setState(() {});
          _controller.forward();
        }
      }
    } catch (e) {
      debugPrint("Erreur chargement feedback: $e");
    }
  }

  Future<void> _submitFeedback() async {
    if (_isSubmitting || _rating == 0 || _reservationData == null) return;

    setState(() => _isSubmitting = true);

    try {
      final feedbackData = {
        'reservationId': widget.reservationId,
        'driverId': _reservationData!['driverId'],
        'passengerId': _reservationData!['userId'],
        'fromDriver': false,
        'rating': _rating,
        'comment': _commentController.text.trim(),
        'tags': _selectedTags.toList(),
        'recommend': _recommend,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('feedbacks')
          .add(feedbackData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: AppColors.gold),
              SizedBox(width: 12),
              Expanded(
                child: Text("Merci pour votre évaluation !",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          backgroundColor: Colors.black.withOpacity(0.95),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.gold, width: 1),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          duration: const Duration(seconds: 3),
          elevation: 12,
        ),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Envoi impossible : $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

    final from = (_reservationData!['from'] ?? 'Départ inconnu').toString();
    final to = (_reservationData!['to'] ?? 'Arrivée inconnue').toString();
    final price = ((_reservationData!['price'] ?? 0) as num).toDouble();
    final timestamp = _reservationData!['timestamp'];
    final date = timestamp is Timestamp
        ? DateFormat.yMMMMd('fr_FR').add_Hm().format(timestamp.toDate())
        : 'Date inconnue';

    final driverName =
        "${_driverData!['firstName'] ?? ''} ${_driverData!['lastName'] ?? ''}"
            .trim();
    final driverPhoto = _driverData!['photoUrl'];

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.gold),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        centerTitle: true,
        title: const Text(
          "Noter le chauffeur",
          style: TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // médaillon
              Center(
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Colors.black, size: 40),
                ),
              ),
              const SizedBox(height: 14),
              const _GoldText(
                "Comment s’est passé votre trajet ?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'PlayfairDisplay',
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),

              // carte trajet
              _GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TripHeader(price: price, date: date),
                    const SizedBox(height: 12),
                    _Timeline(from: from, to: to),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // carte chauffeur
              _GlassCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.black,
                      backgroundImage: (driverPhoto != null &&
                              driverPhoto.toString().isNotEmpty)
                          ? NetworkImage(driverPhoto.toString())
                          : null,
                      child: (driverPhoto == null ||
                              driverPhoto.toString().isEmpty)
                          ? const Icon(Icons.person,
                              color: AppColors.gold, size: 30)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverName.isEmpty ? "Conducteur" : driverName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'PlayfairDisplay',
                              fontSize: 16.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text("Votre chauffeur",
                              style: TextStyle(color: Colors.white60)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // notation
              const Text(
                "Attribuez une note",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: RatingBar.builder(
                  initialRating: 0,
                  minRating: 1,
                  allowHalfRating: false,
                  itemSize: 36,
                  unratedColor: Colors.white24,
                  itemPadding: const EdgeInsets.symmetric(horizontal: 6.0),
                  itemBuilder: (context, _) =>
                      const Icon(Icons.star_rounded, color: AppColors.gold),
                  onRatingUpdate: (rating) => setState(() => _rating = rating),
                ),
              ),
              const SizedBox(height: 18),

              // tags rapides
              const Text(
                "Points forts (optionnel)",
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickTags.map((t) {
                  final sel = _selectedTags.contains(t);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        sel ? _selectedTags.remove(t) : _selectedTags.add(t);
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: sel ? null : const Color(0xFF151515),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: sel ? const Color(0xFFFFE680) : Colors.white12,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: AppColors.gold.withOpacity(.22),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                )
                              ]
                            : [],
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          color: sel ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // recommander
              Row(
                children: [
                  const Icon(Icons.thumb_up_alt_rounded, color: AppColors.gold),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text("Recommander ce chauffeur",
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ),
                  Switch(
                    value: _recommend,
                    activeColor: AppColors.gold,
                    onChanged: (v) => setState(() => _recommend = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // commentaire
              TextField(
                controller: _commentController,
                maxLines: 4,
                maxLength: 250,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Laisser un commentaire (optionnel)",
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
              const SizedBox(height: 18),

              // bouton
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                      (_rating == 0 || _isSubmitting) ? null : _submitFeedback,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.black),
                  label: Text(
                    _isSubmitting ? "Envoi..." : "Envoyer la note",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
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

/* ==================== WIDGETS PREMIUM ==================== */

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(0.16), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.45),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GoldText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _GoldText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class _TripHeader extends StatelessWidget {
  final double price;
  final String date;
  const _TripHeader({required this.price, required this.date});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.receipt_long_rounded, color: AppColors.gold, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Résumé du trajet",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.5,
              fontFamily: 'PlayfairDisplay',
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Les chips peuvent passer à la ligne si l’espace manque
        Flexible(
          fit: FlexFit.loose,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.end,
            children: [
              _DistancePill(text: date),
              _PricePill(
                  value: "${price.toStringAsFixed(2).replaceAll('.', ',')} €"),
            ],
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final String from;
  final String to;
  const _Timeline({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
            ),
            border: Border.all(color: Color(0xFFFFEAB0), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(.35),
                blurRadius: 6,
                spreadRadius: 1,
              )
            ],
          ),
        );

    final labelStyle = TextStyle(
      color: AppColors.gold.withOpacity(.95),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    const valueStyle = TextStyle(
      color: Colors.white,
      fontSize: 15.5,
      fontFamily: 'PlayfairDisplay',
      fontWeight: FontWeight.w700,
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          dot(),
          Container(
            width: 2,
            height: 24,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
              ),
            ),
          ),
          dot(),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Départ', style: labelStyle),
              const SizedBox(height: 2),
              Text(from, maxLines: 1, style: valueStyle),
              const SizedBox(height: 8),
              Text('Arrivée', style: labelStyle),
              const SizedBox(height: 2),
              Text(to, maxLines: 1, style: valueStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/* ====== petites pilules ====== */

class _PricePill extends StatelessWidget {
  final String value;
  const _PricePill({required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFFFE680), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }
}

class _DistancePill extends StatelessWidget {
  final String text;
  const _DistancePill({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w800,
          color: AppColors.gold,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }
}
