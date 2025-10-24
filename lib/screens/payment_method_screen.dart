import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';

import '../themes/app_theme.dart'; // AppColors.gold / deepGold / black

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});
  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  bool _loading = true;
  bool _working = false;

  String? _defaultPmId;
  List<_PmView> _methods = [];

  @override
  void initState() {
    super.initState();
    _fetchMethods();
  }

  // ----------------------------- Backend calls -----------------------------

  Future<void> _fetchMethods() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _methods = [];
        _defaultPmId = null;
        _loading = false;
      });
      return;
    }
    try {
      setState(() => _loading = true);
      final callable =
          FirebaseFunctions.instance.httpsCallable('listPaymentMethods');
      final resp = await callable.call();
      final data = (resp.data as Map);
      final defId = data['defaultPaymentMethod'] as String?;
      final list = (data['methods'] as List).cast<Map>();

      final mapped = list
          .map((m) => _PmView(
                id: (m['id'] ?? '') as String,
                brand: (m['brand'] ?? '') as String,
                last4: (m['last4'] ?? '') as String,
                expMonth: (m['expMonth'] ?? 0) as int,
                expYear: (m['expYear'] ?? 0) as int,
              ))
          .toList();

      setState(() {
        _defaultPmId = defId;
        _methods = mapped;
      });
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? e.code;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement des cartes : $msg')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement des cartes : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCardMobile() async {
    try {
      setState(() => _working = true);
      final createSetup =
          FirebaseFunctions.instance.httpsCallable('createSetupIntent');
      final resp = await createSetup.call(); // { clientSecret, customerId }
      final clientSecret = (resp.data['clientSecret'] as String);
      final customerId = (resp.data['customerId'] as String);

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          merchantDisplayName: 'Ride My Way',
          setupIntentClientSecret: clientSecret,
          customerId: customerId,
          style: ThemeMode.dark,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: AppColors.gold,
              background: Colors.black,
            ),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Carte ajoutée')),
      );
      await _fetchMethods();
    } catch (e) {
      if (!mounted) return;
      final msg = e is StripeException
          ? e.error.localizedMessage ?? e.toString()
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ajout annulé/échoué : $msg')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openStripePortalWeb() async {
    try {
      final returnUrl = Uri.base.toString(); // revient sur la page courante
      final callable = FirebaseFunctions.instance
          .httpsCallable('createCustomerPortalSession');
      final resp = await callable.call({'returnUrl': returnUrl});
      final url = Uri.parse(resp.data['url'] as String);
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Stripe : ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _setDefault(String pmId) async {
    try {
      setState(() => _working = true);
      final fn =
          FirebaseFunctions.instance.httpsCallable('setDefaultPaymentMethod');
      await fn.call({'paymentMethodId': pmId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Définie comme carte par défaut')),
      );
      await _fetchMethods();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove(String pmId) async {
    try {
      setState(() => _working = true);
      final fn =
          FirebaseFunctions.instance.httpsCallable('detachPaymentMethod');
      await fn.call({'paymentMethodId': pmId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Carte supprimée')),
      );
      await _fetchMethods();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // --------------------------------- UI ---------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        leading: IconButton(
          icon: const GoldIcon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const GradientText(
          'Paiements sécurisés',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: Colors.black,
        onRefresh: _fetchMethods,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionCard(
              title: Row(
                children: const [
                  GoldIcon(Icons.verified_user_rounded, size: 18, glow: true),
                  SizedBox(width: 8),
                  GradientText('Conformité & sécurité',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              children: const [
                Text(
                  'Vos paiements sont traités par Stripe (PCI-DSS). '
                  'La carte est ajoutée lors de la réservation (3-D Secure). '
                  'Nous ne stockons jamais vos numéros.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: Row(
                children: const [
                  GoldIcon(Icons.credit_card_rounded, size: 18, glow: true),
                  SizedBox(width: 8),
                  GradientText('Vos cartes',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.gold)),
                  )
                else if (_methods.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      kIsWeb
                          ? 'Aucune carte enregistrée. Gérez/ajoutez vos cartes depuis votre espace Stripe.'
                          : 'Aucune carte enregistrée. Ajoutez une carte pour sécuriser vos paiements.',
                      style: TextStyle(color: Colors.white70.withOpacity(.95)),
                    ),
                  )
                else
                  Column(
                    children: _methods
                        .map((m) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _pmTile(
                                m,
                                isDefault: m.id == _defaultPmId,
                                onSetDefault: () => _setDefault(m.id),
                                onRemove: () => _remove(m.id),
                              ),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                if (!kIsWeb)
                  _primaryGoldButton(
                    icon: Icons.add_card_rounded,
                    label: _working ? 'Traitement…' : 'Ajouter une carte',
                    onTap: _working ? null : _addCardMobile,
                  )
                else
                  _primaryGoldButton(
                    icon: Icons.open_in_new_rounded,
                    label: 'Gérer mes paiements (Stripe)',
                    onTap: _openStripePortalWeb,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: Row(
                children: const [
                  GoldIcon(Icons.receipt_long_rounded, size: 18, glow: true),
                  SizedBox(width: 8),
                  GradientText('Historique des paiements',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              children: const [
                _ReceiptRow(
                    'Trajet du 12/10 — Classe E', 'Pré-autorisé • 28,00 €'),
                _ReceiptRow('Trajet du 10/10 — Berline', 'Capturé • 16,50 €'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 16), ...children],
      ),
    );
  }

  Widget _pmTile(
    _PmView m, {
    required bool isDefault,
    required VoidCallback onSetDefault,
    required VoidCallback onRemove,
  }) {
    final exp = (m.expMonth > 0 && m.expYear > 0)
        ? '${m.expMonth.toString().padLeft(2, '0')}/${m.expYear}'
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const GoldIcon(Icons.credit_card_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${m.brand.isEmpty ? 'Carte' : m.brand} •••• ${m.last4} — exp. $exp',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: Premium.goldGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Par défaut',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (v) {
              if (v == 'default') onSetDefault();
              if (v == 'remove') onRemove();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'default', child: Text('Définir par défaut')),
              PopupMenuItem(value: 'remove', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _primaryGoldButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.deepGold.withOpacity(.20),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            gradient: Premium.goldGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GoldIcon(icon, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------- Small models/widgets -----------------------------

class _PmView {
  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  _PmView({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
  });
}

// Helpers visuels (retire-les si tu as déjà ces widgets globalement)
class Premium {
  static const goldGradient = LinearGradient(
    colors: [AppColors.gold, AppColors.deepGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class GoldIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool glow;
  const GoldIcon(this.icon, {super.key, this.size = 20, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon, color: Colors.white, size: size);
    final masked = ShaderMask(
      shaderCallback: (rect) => Premium.goldGradient.createShader(rect),
      blendMode: BlendMode.srcIn,
      child: base,
    );
    if (!glow) return masked;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.26),
            blurRadius: 18,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: masked,
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => Premium.goldGradient.createShader(r),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String title;
  final String subtitle;
  const _ReceiptRow(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const GoldIcon(Icons.receipt_rounded, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white))),
        GradientText(subtitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
