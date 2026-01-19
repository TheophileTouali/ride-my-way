import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class AdminPassengersScreen extends StatefulWidget {
  const AdminPassengersScreen({super.key});

  @override
  State<AdminPassengersScreen> createState() => _AdminPassengersScreenState();
}

class _AdminPassengersScreenState extends State<AdminPassengersScreen>
    with SingleTickerProviderStateMixin {
  String _query = '';
  String _filter =
      'all'; // all | complete | incomplete | pending | verified | rejected

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PASSENGER RULES
  // ─────────────────────────────────────────────────────────────────────────────

  // "Complet" = birthdate + address + identityCardUrl
  bool _isProfileComplete(Map<String, dynamic> d) {
    final hasBirth = _hasBirthdate(d);
    final addr = (d['address'] ?? '').toString().trim();
    final id = (d['identityCardUrl'] ?? '').toString().trim();
    return hasBirth && addr.isNotEmpty && id.isNotEmpty;
  }

  bool _hasBirthdate(Map<String, dynamic> d) => _asDate(d['birthdate']) != null;

  bool _birthValidated(Map<String, dynamic> d) =>
      (d['birthdateValidated'] ?? false) == true;

  String _status(Map<String, dynamic> d) {
    return (d['verificationStatus'] ??
            d['status'] ??
            d['verification_status'] ??
            'pending')
        .toString();
  }

  bool _canBook(Map<String, dynamic> d) {
    return (d['canBookRides'] ??
            d['can_book_rides'] ??
            d['canBookRide'] ??
            false) ==
        true;
  }

  bool _matchFilter(Map<String, dynamic> d) {
    final complete = _isProfileComplete(d);
    final s = _status(d);
    switch (_filter) {
      case 'complete':
        return complete;
      case 'incomplete':
        return !complete;
      case 'pending':
        return s == 'pending';
      case 'verified':
        return s == 'verified';
      case 'rejected':
        return s == 'rejected';
      default:
        return true;
    }
  }

  bool _matchQuery(Map<String, dynamic> d) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();

    final fullName =
        '${(d['firstName'] ?? '')} ${(d['lastName'] ?? '')}'.toLowerCase();
    final email = (d['email'] ?? '').toString().toLowerCase();
    final phone = (d['phone'] ?? '').toString().toLowerCase();
    final address = (d['address'] ?? '').toString().toLowerCase();

    return fullName.contains(q) ||
        email.contains(q) ||
        phone.contains(q) ||
        address.contains(q);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DATE helpers
  // ─────────────────────────────────────────────────────────────────────────────
  String _fmtDate(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year.toString();
    return '$dd/$mm/$yy';
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // support "dd/MM/yyyy"
    final parts = s.split(RegExp(r'[/\-]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  String _birthLabel(dynamic birth) {
    final dt = _asDate(birth);
    return dt == null ? '' : _fmtDate(dt);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // FIRESTORE ACTIONS
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _validateBirthdate({
    required String uid,
    required String reviewedBy,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'birthdateValidated': true,
      'reviewedBy': reviewedBy,
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setVerificationStatus({
    required String uid,
    required String status, // pending | verified | rejected
    required String reviewedBy,
    bool? canBookRides,
  }) async {
    final patch = <String, dynamic>{
      'verificationStatus': status,
      'reviewedBy': reviewedBy,
      'reviewedAt': FieldValue.serverTimestamp(),
    };
    if (canBookRides != null) patch['canBookRides'] = canBookRides;

    await FirebaseFirestore.instance.collection('users').doc(uid).set(
          patch,
          SetOptions(merge: true),
        );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          // Fond “ink”
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B0B0D), Color(0xFF08080A)],
                ),
              ),
            ),
          ),

          // Orbes dorées
          Positioned(
            right: -160,
            top: -120,
            width: 420,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.gold.withOpacity(.14), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -130,
            width: 380,
            height: 380,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.deepGold.withOpacity(.10),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(context),
                      const SizedBox(height: 12),
                      _glass(
                        radius: 22,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          children: [
                            _liveStrip(),
                            const SizedBox(height: 10),
                            _searchField(),
                            const SizedBox(height: 10),
                            _filtersRow(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(child: _list()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        _GoldTitle("Super Admin • Passagers"),
        const SizedBox(width: 10),
        const _LiveChip(),
        const Spacer(),
        _IconGlassBtn(
          icon: Icons.arrow_back_rounded,
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/admin');
            }
          },
        ),
      ],
    );
  }

  Widget _liveStrip() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'passenger')
          .snapshots(),
      builder: (context, snap) {
        final total = snap.data?.docs.length ?? 0;
        int complete = 0;
        int verified = 0;
        int pending = 0;
        int rejected = 0;

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final d = doc.data();
            if (_isProfileComplete(d)) complete++;

            final s = _status(d).toLowerCase().trim();
            if (s == 'verified') verified++;
            if (s == 'pending') pending++;
            if (s == 'rejected') rejected++;
          }
        }

        return LayoutBuilder(
          builder: (context, c) {
            final isNarrow = c.maxWidth < 720;

            final tiles = <Widget>[
              _MiniKpi(
                title: "Total",
                value: "$total",
                icon: Icons.people_alt_rounded,
              ),
              _MiniKpi(
                title: "Complets",
                value: "$complete",
                icon: Icons.verified_rounded,
                good: true,
              ),
              _MiniKpi(
                title: "Pending",
                value: "$pending",
                icon: Icons.hourglass_bottom_rounded,
                warn: true,
              ),
              _MiniKpi(
                title: "Verified",
                value: "$verified",
                icon: Icons.verified_user_rounded,
                good: true,
              ),
              _MiniKpi(
                title: "Rejected",
                value: "$rejected",
                icon: Icons.block_rounded,
                bad: true,
              ),
            ];

            if (!isNarrow) {
              // tablette/desktop : 1 ligne
              return Row(
                children: [
                  for (int i = 0; i < tiles.length; i++) ...[
                    Expanded(child: tiles[i]),
                    if (i != tiles.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            }

            // mobile : 2 colonnes (plus d’overflow)
            final w = (c.maxWidth - 10) / 2; // 10 = spacing
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final t in tiles) SizedBox(width: w, child: t),
              ],
            );
          },
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
        hintText: "Rechercher (nom, email, tel, adresse)…",
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.gold.withOpacity(.85)),
        ),
      ),
    );
  }

  Widget _filtersRow() {
    final items = const [
      ('Tous', 'all'),
      ('Complets', 'complete'),
      ('Incomplets', 'incomplete'),
      ('Pending', 'pending'),
      ('Verified', 'verified'),
      ('Rejected', 'rejected'),
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items
              .map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterPill(
                      label: e.$1,
                      selected: _filter == e.$2,
                      onTap: () => setState(() => _filter = e.$2),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _list() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          );
        }

        final docs = snap.data!.docs.where((doc) {
          final data = doc.data();
          return _matchFilter(data) && _matchQuery(data);
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Text("Aucun passager trouvé.",
                style: TextStyle(color: Colors.white60)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data();
            final uid = doc.id;

            final fullName =
                "${d['firstName'] ?? ''} ${d['lastName'] ?? ''}".trim();
            final email = (d['email'] ?? '').toString();
            final phone = (d['phone'] ?? '').toString();
            final address = (d['address'] ?? '').toString().trim();

            final hasBirth = _hasBirthdate(d);
            final birthLabel = _birthLabel(d['birthdate']);
            final birthValidated = _birthValidated(d);

            final idCardUrl = (d['identityCardUrl'] ?? '').toString().trim();
            final hasIdCard = idCardUrl.isNotEmpty;

            final canBook = _canBook(d);

            final status = _status(d);
            final complete = _isProfileComplete(d);

            return AnimatedBuilder(
              animation: _glow,
              builder: (_, __) {
                final glow = 0.10 + 0.10 * _glow.value;

                return _glass(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  borderGlowOpacity: complete ? glow : 0.06,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Medallion(
                        icon: Icons.person_rounded,
                        status: status,
                        complete: complete,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ligne 1 : nom + pills
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fullName.isEmpty ? uid : fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'PlayfairDisplay',
                                      fontSize: 16,
                                      letterSpacing: .15,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _StatusPill(status: status),
                                const SizedBox(width: 8),
                                _BadgePill(
                                  text: complete ? "Complet" : "Incomplet",
                                  color: complete
                                      ? const Color(0xFF45E27A)
                                      : const Color(0xFFE55B5B),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            _InfoLine(icon: Icons.email_rounded, text: email),
                            const SizedBox(height: 2),
                            _InfoLine(
                                icon: Icons.phone_android_rounded, text: phone),
                            if (address.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _InfoLine(
                                  icon: Icons.location_on_rounded,
                                  text: address),
                            ],

                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _BadgePill(
                                  text: hasBirth
                                      ? "Birthdate: $birthLabel"
                                      : "Birthdate manquante",
                                  color: hasBirth
                                      ? AppColors.gold
                                      : const Color(0xFFE55B5B),
                                  dark: true,
                                ),
                                _BadgePill(
                                  text: birthValidated
                                      ? "Birthdate VALIDÉE"
                                      : "Birthdate NON validée",
                                  color: birthValidated
                                      ? const Color(0xFF45E27A)
                                      : const Color(0xFFFFC44D),
                                  dark: true,
                                ),
                                _BadgePill(
                                  text: hasIdCard
                                      ? "Carte ID: OK"
                                      : "Carte ID manquante",
                                  color: hasIdCard
                                      ? const Color(0xFF45E27A)
                                      : const Color(0xFFE55B5B),
                                  dark: true,
                                ),
                                _BadgePill(
                                  text: canBook
                                      ? "Réservations: ON"
                                      : "Réservations: OFF",
                                  color: canBook
                                      ? const Color(0xFF45E27A)
                                      : const Color(0xFFE55B5B),
                                  dark: true,
                                ),
                                _LuxAction(
                                  label: "Valider birthdate",
                                  icon: Icons.verified_rounded,
                                  enabled: hasBirth && !birthValidated,
                                  onTap: () async {
                                    await _validateBirthdate(
                                        uid: uid, reviewedBy: "Admin");
                                    if (!mounted) return;
                                    _toast("✅ Birthdate validée");
                                  },
                                ),
                                _LuxAction(
                                  label: "Marquer VERIFIED",
                                  icon: Icons.verified_user_rounded,
                                  enabled: complete && birthValidated,
                                  onTap: () async {
                                    await _setVerificationStatus(
                                      uid: uid,
                                      status: 'verified',
                                      reviewedBy: "Admin",
                                      canBookRides: true,
                                    );
                                    if (!mounted) return;
                                    _toast(
                                        "✅ Passager vérifié (canBookRides = true)");
                                  },
                                ),
                                _LuxAction(
                                  label: "Reject",
                                  icon: Icons.block_rounded,
                                  danger: true,
                                  enabled: true,
                                  onTap: () async {
                                    await _setVerificationStatus(
                                      uid: uid,
                                      status: 'rejected',
                                      reviewedBy: "Admin",
                                      canBookRides: false,
                                    );
                                    if (!mounted) return;
                                    _toast(
                                        "⛔ Passager rejeté (canBookRides = false)");
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _IconGlassBtn(
                        icon: Icons.chevron_right_rounded,
                        onTap: () => _openDetails(uid, d),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DETAILS SHEET (lux)
  // ─────────────────────────────────────────────────────────────────────────────
  void _openDetails(String uid, Map<String, dynamic> d) {
    // controllers (text)
    final cFirst =
        TextEditingController(text: (d['firstName'] ?? '').toString());
    final cLast = TextEditingController(text: (d['lastName'] ?? '').toString());
    final cEmail = TextEditingController(text: (d['email'] ?? '').toString());
    final cPhone = TextEditingController(text: (d['phone'] ?? '').toString());
    final cAddress =
        TextEditingController(text: (d['address'] ?? '').toString());

    // birthdate
    DateTime? birthDt = _asDate(d['birthdate']);

    // status + booleans
    String status = _status(d);
    final Map<String, bool> bools = {};
    for (final e in d.entries) {
      if (e.value is bool) {
        bools[e.key] = e.value as bool;
      }
    }
    bools.putIfAbsent('canBookRides', () => _canBook(d));
    bools.putIfAbsent('birthdateValidated', () => _birthValidated(d));
    bools.putIfAbsent('isVisible', () => (d['isVisible'] ?? true) == true);

    final identityCardUrl = (d['identityCardUrl'] ?? '').toString().trim();
    final photoUrl = (d['photoUrl'] ?? '').toString().trim();

    Future<void> save() async {
      final patch = <String, dynamic>{
        'firstName': cFirst.text.trim(),
        'lastName': cLast.text.trim(),
        'email': cEmail.text.trim(),
        'phone': cPhone.text.trim(),
        'address': cAddress.text.trim(),
        'verificationStatus': status,
        'reviewedBy': 'Admin',
        'reviewedAt': FieldValue.serverTimestamp(),
        ...bools,
      };

      if (birthDt != null) {
        patch['birthdate'] = Timestamp.fromDate(birthDt!);
      } else {
        patch['birthdate'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(patch, SetOptions(merge: true));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (ctx, scroll) {
          return StatefulBuilder(
            builder: (ctx, setSheet) {
              Widget field({
                required String label,
                required TextEditingController controller,
                IconData? icon,
                TextInputType? keyboardType,
              }) {
                return _glass(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: controller,
                        keyboardType: keyboardType,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          prefixIcon: icon == null
                              ? null
                              : Icon(icon, color: Colors.white54, size: 18),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.white10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.white10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: AppColors.gold.withOpacity(.85)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget boolTile(String key, bool value) {
                return _glass(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Switch(
                        value: value,
                        activeColor: AppColors.gold,
                        onChanged: (v) => setSheet(() => bools[key] = v),
                      )
                    ],
                  ),
                );
              }

              Widget statusPills() {
                Widget pill(String s, Color c) {
                  final selected = status == s;
                  return InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setSheet(() => status = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: selected
                            ? c.withOpacity(.18)
                            : const Color(0xFF101010),
                        border: Border.all(
                            color:
                                selected ? c.withOpacity(.7) : Colors.white12),
                      ),
                      child: Text(
                        s.toUpperCase(),
                        style: TextStyle(
                          color: selected ? c : Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: .12,
                        ),
                      ),
                    ),
                  );
                }

                return Row(
                  children: [
                    pill('pending', const Color(0xFFFFC44D)),
                    const SizedBox(width: 8),
                    pill('verified', const Color(0xFF45E27A)),
                    const SizedBox(width: 8),
                    pill('rejected', const Color(0xFFE55B5B)),
                  ],
                );
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F10),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: Colors.white10, width: 1),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54,
                        blurRadius: 26,
                        offset: Offset(0, -10)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                      children: [
                        Row(
                          children: [
                            const _SheetHandle(),
                            const Spacer(),
                            _IconGlassBtn(
                              icon: Icons.close_rounded,
                              onTap: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const _GoldTitle("Détails passager"),
                        const SizedBox(height: 10),
                        _glass(
                          radius: 18,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              _kv("UID", uid),
                              _kv("Complet",
                                  _isProfileComplete(d) ? "Oui" : "Non"),
                              _kv("Birthdate",
                                  birthDt == null ? "—" : _fmtDate(birthDt!)),
                              _kv("Carte ID",
                                  identityCardUrl.isEmpty ? "—" : "OK"),
                              _kv("Photo", photoUrl.isEmpty ? "—" : "OK"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _GoldTitle("Statut"),
                        const SizedBox(height: 10),
                        statusPills(),
                        const SizedBox(height: 12),
                        const _GoldTitle("Identité & Contact"),
                        const SizedBox(height: 10),
                        field(
                            label: "Prénom",
                            controller: cFirst,
                            icon: Icons.person_rounded),
                        const SizedBox(height: 10),
                        field(
                            label: "Nom",
                            controller: cLast,
                            icon: Icons.person_outline_rounded),
                        const SizedBox(height: 10),
                        field(
                            label: "Email",
                            controller: cEmail,
                            icon: Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: 10),
                        field(
                            label: "Téléphone",
                            controller: cPhone,
                            icon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone),
                        const SizedBox(height: 10),
                        field(
                            label: "Adresse",
                            controller: cAddress,
                            icon: Icons.location_on_rounded,
                            keyboardType: TextInputType.streetAddress),
                        const SizedBox(height: 12),
                        const _GoldTitle("Birthdate"),
                        const SizedBox(height: 10),
                        _glass(
                          radius: 18,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  birthDt == null
                                      ? "Aucune date"
                                      : _fmtDate(birthDt!),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              _IconGlassBtn(
                                icon: Icons.date_range_rounded,
                                onTap: () async {
                                  final initial =
                                      birthDt ?? DateTime(2000, 1, 1);
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: initial,
                                    firstDate: DateTime(1940, 1, 1),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setSheet(() => birthDt = picked);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _GoldTitle("Booléens"),
                        const SizedBox(height: 10),
                        ...bools.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: boolTile(e.key, e.value),
                            )),
                        const SizedBox(height: 14),
                        _LuxAction(
                          label: "Sauvegarder",
                          icon: Icons.save_rounded,
                          enabled: true,
                          onTap: () async {
                            await save();
                            if (!mounted) return;
                            Navigator.of(ctx).pop();
                            _toast("✅ Modifications enregistrées");
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers UI
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _glass({
    required double radius,
    required EdgeInsets padding,
    required Widget child,
    double borderGlowOpacity = 0.08,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [Colors.white.withOpacity(0.06), Colors.black12],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          const BoxShadow(
              color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
          BoxShadow(
            color: AppColors.gold.withOpacity(borderGlowOpacity),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
              child: Text(k, style: const TextStyle(color: Colors.white60))),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black87,
        content: Text(msg, style: const TextStyle(color: AppColors.gold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium atoms (identiques)
/// ─────────────────────────────────────────────────────────────────────────────
class _GoldTitle extends StatelessWidget {
  final String text;
  const _GoldTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _LiveChip extends StatefulWidget {
  const _LiveChip();

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: .92, end: 1.0)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: const Color(0xFF151515),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF45E27A),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF45E27A).withOpacity(.6),
                    blurRadius: 10)
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text("LIVE",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}

class _IconGlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconGlassBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(.06), Colors.black12],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white10),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
          ],
        ),
        child: Icon(icon, color: AppColors.gold),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : const Color(0xFF121212),
          border:
              Border.all(color: selected ? Colors.transparent : Colors.white12),
          boxShadow: selected
              ? const [
                  BoxShadow(
                      color: Color(0x33FFD700),
                      blurRadius: 16,
                      offset: Offset(0, 8)),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: .15,
          ),
        ),
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool good;
  final bool warn;
  final bool bad;

  const _MiniKpi({
    required this.title,
    required this.value,
    required this.icon,
    this.good = false,
    this.warn = false,
    this.bad = false,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = AppColors.gold;
    if (good) accent = const Color(0xFF45E27A);
    if (warn) accent = const Color(0xFFFFC44D);
    if (bad) accent = const Color(0xFFE55B5B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(.12),
              border: Border.all(color: accent.withOpacity(.35)),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  final IconData icon;
  final String status;
  final bool complete;

  const _Medallion({
    required this.icon,
    required this.status,
    required this.complete,
  });

  @override
  Widget build(BuildContext context) {
    final Color ring = complete ? const Color(0xFF45E27A) : AppColors.gold;
    final Color dot = status == 'verified'
        ? const Color(0xFF45E27A)
        : status == 'rejected'
            ? const Color(0xFFE55B5B)
            : const Color(0xFFFFC44D);

    return Stack(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFE08A), Color(0xFFA87C00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Icon(icon, color: Colors.black),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot,
              border: Border.all(color: ring.withOpacity(.8), width: 2),
              boxShadow: [
                BoxShadow(color: dot.withOpacity(.55), blurRadius: 10)
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'verified':
        c = const Color(0xFF45E27A);
        break;
      case 'rejected':
        c = const Color(0xFFE55B5B);
        break;
      default:
        c = const Color(0xFFFFC44D);
    }
    return _BadgePill(text: status.toUpperCase(), color: c);
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  final Color color;
  final bool dark;

  const _BadgePill(
      {required this.text, required this.color, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: dark ? const Color(0xFF0F0F10) : color.withOpacity(.12),
        border: Border.all(color: color.withOpacity(dark ? .30 : .55)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: dark ? Colors.white70 : color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: .1,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _LuxAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool danger;

  const _LuxAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_LuxAction> createState() => _LuxActionState();
}

class _LuxActionState extends State<_LuxAction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final grad = widget.danger
        ? const [Color(0xFFFF6B6B), Color(0xFFD24545)]
        : const [Color(0xFFFFD700), Color(0xFFA87C00)];

    return Opacity(
      opacity: widget.enabled ? 1 : .40,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _down ? 0.985 : 1,
        child: InkWell(
          onHighlightChanged: (v) => setState(() => _down = v),
          onTap: widget.enabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(colors: grad),
              boxShadow: [
                BoxShadow(
                  color: (widget.danger ? Colors.redAccent : AppColors.gold)
                      .withOpacity(.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon, size: 16, color: Colors.black),
              const SizedBox(width: 8),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .15,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
