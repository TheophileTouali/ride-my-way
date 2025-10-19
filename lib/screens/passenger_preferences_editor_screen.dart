import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/passenger_preferences.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

class PassengerPreferencesEditorScreen extends StatefulWidget {
  const PassengerPreferencesEditorScreen({super.key});

  @override
  State<PassengerPreferencesEditorScreen> createState() =>
      _PassengerPreferencesEditorScreenState();
}

class _PassengerPreferencesEditorScreenState
    extends State<PassengerPreferencesEditorScreen> {
  late PassengerPreferences prefs;

  @override
  void initState() {
    super.initState();
    final original =
        Provider.of<UserProvider>(context, listen: false).preferences;
    prefs = original.copyWith(); // on édite une copie
    _sanitizePrefs();
  }

  // ———————————————————————————————————————————————————————————
  // Normalisation douce pour éviter les valeurs hors-liste
  // + cohérence initiale des dépendances
  // ———————————————————————————————————————————————————————————
  void _sanitizePrefs() {
    const ambienceOptions = ["Silencieux", "Discret", "Dynamique", "Libre"];
    if (!ambienceOptions.contains(prefs.ambiance)) {
      prefs = prefs.copyWith(ambiance: ambienceOptions.first);
    }
    if (prefs.conversation == 'Discussion conviviale') {
      prefs = prefs.copyWith(conversation: 'Discussion légère');
    }

    // Dépendances
    if (!prefs.music) {
      prefs = prefs.copyWith(musicStyle: 'Aucun');
    } else if (prefs.ambiance == 'Silencieux') {
      prefs = prefs.copyWith(musicStyle: 'Aucun');
    }

    if (!prefs.temperature) {
      prefs = prefs.copyWith(temperatureLevel: null);
    }
    if (!prefs.perfume) {
      prefs = prefs.copyWith(scentLevel: null);
    }

    // Si pas Moto, on nettoie les champs moto
    if (prefs.vehicleType != 'Moto') {
      prefs = prefs.copyWith(
        helmetType: null,
        helmetHygiene: null,
        protections: null,
        motoSpeed: null,
        intercom: null,
      );
    }
  }

  // ———————————————————————————————————————————————————————————
  // Helpers logiques pour l'affichage conditionnel
  // ———————————————————————————————————————————————————————————
  bool get _showMusicStyle => prefs.music && prefs.ambiance != 'Silencieux';
  bool get _showTemperatureLevel => prefs.temperature;
  bool get _showScentLevel => prefs.perfume;
  bool get _isMoto => prefs.vehicleType == 'Moto';
  bool get _showAmbientLight => !_isMoto; // Pas pertinent pour Moto

  void savePreferences() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    userProvider.updatePreferences(prefs);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Préférences mises à jour avec succès.",
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey[900],
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.black,
        iconTheme: const IconThemeData(color: AppColors.gold),
        title: const _GradientTitle("Modifier mes préférences"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ————————————————— Ambiance
            _PremiumCard(
              title: "🚗 Ambiance & confort intérieur",
              children: [
                _buildDropdown(
                  label: "Ambiance sonore (niveau de musique)",
                  value: prefs.ambiance,
                  options: const [
                    "Silencieux",
                    "Discret",
                    "Dynamique",
                    "Libre"
                  ],
                  onChanged: (v) => setState(() {
                    prefs.ambiance = v ?? prefs.ambiance;
                    // Si “Silencieux”, on force style musical à “Aucun”
                    if (prefs.ambiance == 'Silencieux') {
                      prefs.musicStyle = 'Aucun';
                    }
                  }),
                ),
                if (_showMusicStyle) ...[
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Style musical (genre favori)",
                    value: prefs.musicStyle,
                    options: const [
                      "Aucun",
                      "Jazz",
                      "Lounge",
                      "Afrobeat",
                      "Classique",
                      "Chill"
                    ],
                    onChanged: (v) => setState(() => prefs.musicStyle = v),
                  ),
                ],
                const _GoldDivider(),
                _buildDropdown(
                  label: "Conversation (interaction souhaitée)",
                  value: prefs.conversation,
                  options: const [
                    "Discret",
                    "Discussion légère",
                    "Bavard",
                    "Libre"
                  ],
                  onChanged: (v) => setState(() => prefs.conversation = v),
                ),
                if (_showTemperatureLevel) ...[
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Température (préférence de climatisation)",
                    value: prefs.temperatureLevel,
                    options: const ["Frais", "Tempéré", "Chaud"],
                    onChanged: (v) =>
                        setState(() => prefs.temperatureLevel = v),
                  ),
                ],
                if (_showScentLevel) ...[
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Parfum / désodorisant",
                    value: prefs.scentLevel,
                    options: const ["Aucun", "Léger", "Neutre", "Parfumé"],
                    onChanged: (v) => setState(() => prefs.scentLevel = v),
                  ),
                ],
                if (_showAmbientLight) ...[
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Lumière d’ambiance (premium)",
                    value: prefs.ambientLight,
                    options: const ["Blanc doux", "Ambre", "Bleu nuit", "Or"],
                    onChanged: (v) => setState(() => prefs.ambientLight = v),
                  ),
                ],
                const SizedBox(height: 6),
                _subtitle("Réglages rapides"),
                _buildSwitch(
                  "Playlist exclusive",
                  prefs.music,
                  (val) => setState(() {
                    prefs.music = val;
                    if (!val) {
                      // si OFF, on met le style à "Aucun"
                      prefs.musicStyle = 'Aucun';
                    } else if (prefs.ambiance == 'Silencieux') {
                      // si ambiance silencieuse + ON, on reste sur "Aucun"
                      prefs.musicStyle = 'Aucun';
                    }
                  }),
                ),
                _buildSwitch(
                  "Parfum d’ambiance (on/off)",
                  prefs.perfume,
                  (val) => setState(() {
                    prefs.perfume = val;
                    if (!val) prefs.scentLevel = null;
                  }),
                ),
                _buildSwitch(
                  "Température réglée (on/off)",
                  prefs.temperature,
                  (val) => setState(() {
                    prefs.temperature = val;
                    if (!val) prefs.temperatureLevel = null;
                  }),
                ),
              ],
            ),

            // ————————————————— Confort
            _PremiumCard(
              title: "🪑 Confort physique & ergonomique",
              children: [
                _buildDropdown(
                  label: "Position du siège",
                  value: prefs.seatPosition,
                  options: const ["Avant", "Arrière"],
                  onChanged: (v) => setState(() => prefs.seatPosition = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Réglage du siège",
                  value: prefs.seatIncline,
                  options: const ["Droit", "Incliné"],
                  onChanged: (v) => setState(() => prefs.seatIncline = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Chargeur / USB",
                  value: prefs.chargerUsb,
                  options: const ["Oui", "Non", "Indifférent"],
                  onChanged: (v) => setState(() => prefs.chargerUsb = v),
                ),
                const _GoldDivider(),
                _buildSwitch("Wi-Fi premium", prefs.wifi,
                    (val) => setState(() => prefs.wifi = val)),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Eau / Boisson",
                  value: prefs.water,
                  options: const ["Non", "Plate", "Gazeuse"],
                  onChanged: (v) => setState(() => prefs.water = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Snacks",
                  value: prefs.snacks,
                  options: const ["Non", "Sucré", "Salé"],
                  onChanged: (v) => setState(() => prefs.snacks = v),
                ),
              ],
            ),

            // ————————————————— Environnement
            _PremiumCard(
              title: "🚭 Environnement & hygiène",
              children: [
                _buildSwitch("Véhicule non-fumeur", prefs.smokeFree,
                    (val) => setState(() => prefs.smokeFree = val)),
                _buildSwitch("Véhicule désinfecté", prefs.disinfected ?? false,
                    (val) => setState(() => prefs.disinfected = val)),
                _buildSwitch("Silence à bord", prefs.silentRide ?? false,
                    (val) => setState(() => prefs.silentRide = val)),
                _buildSwitch("Animaux acceptés", prefs.pets,
                    (val) => setState(() => prefs.pets = val)),
              ],
            ),

            // ————————————————— Conduite
            _PremiumCard(
              title: "🏎️ Style de conduite",
              children: [
                _buildDropdown(
                  label: "Conduite",
                  value: prefs.drivingStyle,
                  options: const ["Douce", "Normale", "Dynamique"],
                  onChanged: (v) => setState(() => prefs.drivingStyle = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Vitesse moyenne",
                  value: prefs.avgSpeed,
                  options: const ["Équilibrée", "Rapide"],
                  onChanged: (v) => setState(() => prefs.avgSpeed = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Suspension / type de véhicule",
                  value: prefs.suspension,
                  options: const ["Souple", "Sport"],
                  onChanged: (v) => setState(() => prefs.suspension = v),
                ),
              ],
            ),

            // ————————————————— Esthétique & premium
            _PremiumCard(
              title: "🧥 Esthétique & premium",
              children: [
                _buildDropdown(
                  label: "Type de véhicule",
                  value: prefs.vehicleType,
                  options: const [
                    "Berline",
                    "SUV",
                    "Électrique",
                    "Classe S",
                    "Moto"
                  ],
                  onChanged: (v) => setState(() {
                    prefs.vehicleType = v;
                    // Si on passe à Moto, on nettoie la lumière d’ambiance
                    if (prefs.vehicleType == 'Moto') {
                      prefs.ambientLight = null;
                    } else {
                      // si on quitte Moto, on nettoie les champs moto
                      prefs
                        ..helmetType = null
                        ..helmetHygiene = null
                        ..protections = null
                        ..motoSpeed = null
                        ..intercom = null;
                    }
                  }),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Couleur intérieure",
                  value: prefs.interiorColor,
                  options: const ["Noir", "Beige", "Or"],
                  onChanged: (v) => setState(() => prefs.interiorColor = v),
                ),
                const _GoldDivider(),
                _chipsMulti(
                  label: "Marques préférées",
                  options: const [
                    "Mercedes-Benz",
                    "BMW",
                    "Audi",
                    "Volkswagen",
                    "Porsche",
                    "BMW Motorrad",
                    "Smart",
                    "Aston Martin",
                    "Bentley",
                    "Rolls-Royce",
                    "McLaren",
                    "Jaguar",
                    "Land Rover",
                    "Mini",
                    "Peugeot",
                    "Citroën",
                    "DS Automobiles",
                    "Renault",
                    "Dacia",
                    "Alpine",
                    "Ferrari",
                    "Lamborghini",
                    "Maserati",
                    "Pagani",
                    "Ducati",
                    "Aprilia",
                    "Moto Guzzi",
                    "MV Agusta",
                    "Benelli",
                    "Piaggio",
                    "Vespa",
                    "Seat",
                    "Cupra",
                    "Škoda",
                    "Volvo",
                    "Polestar",
                    "Koenigsegg",
                    "KTM",
                    "Husqvarna",
                    "Triumph",
                    "Rimac",
                    "Energica",
                    "Opel",
                    "Vauxhall",
                    "Tesla",
                  ],
                  values: prefs.brands ?? [],
                  onChanged: (list) =>
                      setState(() => prefs.brands = list.isEmpty ? null : list),
                ),
                const _GoldDivider(),
                _buildSwitch(
                  "Chauffeur attitré",
                  prefs.preferredDriver ?? false,
                  (val) => setState(() => prefs.preferredDriver = val),
                ),
              ],
            ),

            // ————————————————— Moto (uniquement si Moto)
            if (_isMoto)
              _PremiumCard(
                title: "🏍️ Spécifiques moto",
                children: [
                  _buildDropdown(
                    label: "Type de casque",
                    value: prefs.helmetType,
                    options: const ["Intégral", "Modulable", "Jet"],
                    onChanged: (v) => setState(() => prefs.helmetType = v),
                  ),
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Hygiène casque",
                    value: prefs.helmetHygiene,
                    options: const ["Sous-cagoule", "Désinfecté"],
                    onChanged: (v) => setState(() => prefs.helmetHygiene = v),
                  ),
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Tenue / protections",
                    value: prefs.protections,
                    options: const ["Demandées", "Fournies", "Non nécessaires"],
                    onChanged: (v) => setState(() => prefs.protections = v),
                  ),
                  const _GoldDivider(),
                  _buildDropdown(
                    label: "Vitesse de conduite (moto)",
                    value: prefs.motoSpeed,
                    options: const ["Modérée", "Sportive"],
                    onChanged: (v) => setState(() => prefs.motoSpeed = v),
                  ),
                  const _GoldDivider(),
                  _buildSwitch(
                    "Discussion en intercom",
                    prefs.intercom ?? false,
                    (val) => setState(() => prefs.intercom = val),
                  ),
                ],
              ),

            // ————————————————— Écologie
            _PremiumCard(
              title: "🌍 Écologie & éthique",
              children: [
                _buildDropdown(
                  label: "Type d’énergie",
                  value: prefs.energyType,
                  options: const ["Électrique", "Hybride", "Thermique"],
                  onChanged: (v) => setState(() => prefs.energyType = v),
                ),
                const _GoldDivider(),
                _buildSwitch(
                  "Compensation carbone",
                  prefs.carbonOffset ?? false,
                  (val) => setState(() => prefs.carbonOffset = val),
                ),
                _buildSwitch(
                  "Silence moteur",
                  prefs.engineSilence ?? false,
                  (val) => setState(() => prefs.engineSilence = val),
                ),
              ],
            ),

            // ————————————————— Paiement
            _PremiumCard(
              title: "💳 Paiement & réservation",
              children: [
                _buildDropdown(
                  label: "Mode de paiement",
                  value: prefs.paymentMode,
                  options: const ["Automatique", "Manuel", "Partagé"],
                  onChanged: (v) => setState(() => prefs.paymentMode = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Facture",
                  value: prefs.invoiceMethod,
                  options: const ["Email", "SMS"],
                  onChanged: (v) => setState(() => prefs.invoiceMethod = v),
                ),
                const _GoldDivider(),
                _buildDropdown(
                  label: "Notifications",
                  value: prefs.notifications,
                  options: const ["Push", "SMS", "Email"],
                  onChanged: (v) => setState(() => prefs.notifications = v),
                ),
              ],
            ),

            const SizedBox(height: 18),
            _SaveButton(onPressed: savePreferences),
          ],
        ),
      ),
    );
  }

  // ——————————————————— Helpers UI premium ———————————————————

  Widget _subtitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white60,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
        ),
      );

  Widget _buildSwitch(String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500)),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.black,
            activeTrackColor: AppColors.gold,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final String? selected =
        (value != null && options.contains(value)) ? value : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.32),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withOpacity(.28)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                hint: const Text("Sélectionner",
                    style: TextStyle(color: Colors.white54)),
                isExpanded: true,
                dropdownColor: Colors.black,
                iconEnabledColor: AppColors.gold,
                style: const TextStyle(color: Colors.white),
                items: options
                    .map(
                      (o) => DropdownMenuItem<String>(
                        value: o,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(o),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipsMulti({
    required String label,
    required List<String> options,
    required List<String> values,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((brand) {
            final selected = values.contains(brand);
            return FilterChip(
              selected: selected,
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Text(
                  brand,
                  style: TextStyle(
                    color: selected ? AppColors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .2,
                  ),
                ),
              ),
              selectedColor: AppColors.gold,
              backgroundColor: Colors.black.withOpacity(.35),
              showCheckmark: false,
              shape: StadiumBorder(
                side: BorderSide(color: AppColors.gold.withOpacity(.35)),
              ),
              onSelected: (isSel) {
                final next = [...values];
                if (isSel) {
                  if (!next.contains(brand)) next.add(brand);
                } else {
                  next.remove(brand);
                }
                onChanged(next);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ——————————————————— Widgets décoratifs premium ———————————————————

class _PremiumCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _PremiumCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.40),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              colors: [AppColors.gold, AppColors.deepGold],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            fontFamily: 'PlayfairDisplay',
            letterSpacing: .2,
          ),
        ),
      ],
    );
  }
}

class _GoldDivider extends StatelessWidget {
  const _GoldDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(.02),
            AppColors.gold.withOpacity(.35),
            Colors.white.withOpacity(.02),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }
}

class _GradientTitle extends StatelessWidget {
  final String text;
  const _GradientTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.gold, AppColors.deepGold],
      ).createShader(bounds),
      child: const Text(
        "Modifier mes préférences",
        style: TextStyle(
          color: Colors.white, // masqué par le shader
          fontSize: 20,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SaveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 12,
          shadowColor: AppColors.gold.withOpacity(.45),
        ),
        child: const Text(
          "Enregistrer",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: .2,
          ),
        ),
      ),
    );
  }
}
