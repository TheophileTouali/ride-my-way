// lib/models/passenger_preferences.dart
import 'package:flutter/foundation.dart';

class PassengerPreferences {
  // —— Ambiance & musique
  String ambiance; // "Silencieux", "Discret", "Dynamique", "Libre"
  bool music; // ON/OFF musique à bord
  String? musicStyle; // "Aucun", "Jazz", ...
  String? conversation; // "Discret", "Discussion légère", "Bavard", "Libre"
  bool temperature; // ON/OFF réglage température
  String? temperatureLevel; // "Frais", "Tempéré", "Chaud"
  bool perfume; // ON/OFF parfum
  String? scentLevel; // "Aucun", "Léger", "Neutre", "Parfumé"
  String? ambientLight; // "Blanc doux", "Ambre", "Bleu nuit", "Or"

  // —— Confort
  String? seatPosition; // "Avant", "Arrière"
  String? seatIncline; // "Droit", "Incliné"
  String? chargerUsb; // "Oui", "Non", "Indifférent"
  bool wifi; // ON/OFF Wi-Fi
  String? water; // "Non", "Plate", "Gazeuse"
  String? snacks; // "Non", "Sucré", "Salé"

  // —— Environnement
  bool smokeFree; // ON/OFF non-fumeur
  bool? disinfected; // ON/OFF désinfecté
  bool? silentRide; // ON/OFF silence à bord
  bool pets; // ON/OFF animaux

  // —— Conduite
  String? drivingStyle; // "Douce", "Normale", "Dynamique"
  String? avgSpeed; // "Équilibrée", "Rapide"
  String? suspension; // "Souple", "Sport"

  // —— Esthétique/premium
  String? vehicleType; // "Berline","SUV","Électrique","Classe S","Moto"
  String? interiorColor; // "Noir","Beige","Or"
  List<String>? brands; // Marques préférées
  bool? preferredDriver; // ON/OFF chauffeur attitré

  // —— Spécifiques moto
  String? helmetType; // "Intégral","Modulable","Jet"
  String? helmetHygiene; // "Sous-cagoule","Désinfecté"
  String? protections; // "Demandées","Fournies","Non nécessaires"
  String? motoSpeed; // "Modérée","Sportive"
  bool? intercom; // ON/OFF intercom

  // —— Écologie
  String? energyType; // "Électrique","Hybride","Thermique"
  bool? carbonOffset; // ON/OFF compensation
  bool? engineSilence; // ON/OFF silence moteur

  // —— Paiement & réservation
  String? paymentMode; // "Automatique","Manuel","Partagé"
  String? invoiceMethod; // "Email","SMS"
  String? notifications; // "Push","SMS","Email"

  PassengerPreferences({
    // Ambiance
    this.ambiance = "Libre",
    this.music = true,
    this.musicStyle = "Chill",
    this.conversation = "Libre",
    this.temperature = false,
    this.temperatureLevel,
    this.perfume = false,
    this.scentLevel,
    this.ambientLight,

    // Confort
    this.seatPosition,
    this.seatIncline,
    this.chargerUsb,
    this.wifi = false,
    this.water,
    this.snacks,

    // Environnement
    this.smokeFree = true,
    this.disinfected,
    this.silentRide,
    this.pets = false,

    // Conduite
    this.drivingStyle,
    this.avgSpeed,
    this.suspension,

    // Esthétique
    this.vehicleType = "Berline",
    this.interiorColor = "Noir",
    this.brands,
    this.preferredDriver,

    // Moto
    this.helmetType,
    this.helmetHygiene,
    this.protections,
    this.motoSpeed,
    this.intercom,

    // Écologie
    this.energyType = "Électrique",
    this.carbonOffset,
    this.engineSilence,

    // Paiement
    this.paymentMode = "Automatique",
    this.invoiceMethod = "Email",
    this.notifications = "Push",
  });

  PassengerPreferences copyWith({
    String? ambiance,
    bool? music,
    String? musicStyle,
    String? conversation,
    bool? temperature,
    String? temperatureLevel,
    bool? perfume,
    String? scentLevel,
    String? ambientLight,
    String? seatPosition,
    String? seatIncline,
    String? chargerUsb,
    bool? wifi,
    String? water,
    String? snacks,
    bool? smokeFree,
    bool? disinfected,
    bool? silentRide,
    bool? pets,
    String? drivingStyle,
    String? avgSpeed,
    String? suspension,
    String? vehicleType,
    String? interiorColor,
    List<String>? brands,
    bool? preferredDriver,
    String? helmetType,
    String? helmetHygiene,
    String? protections,
    String? motoSpeed,
    bool? intercom,
    String? energyType,
    bool? carbonOffset,
    bool? engineSilence,
    String? paymentMode,
    String? invoiceMethod,
    String? notifications,
  }) {
    return PassengerPreferences(
      ambiance: ambiance ?? this.ambiance,
      music: music ?? this.music,
      musicStyle: musicStyle ?? this.musicStyle,
      conversation: conversation ?? this.conversation,
      temperature: temperature ?? this.temperature,
      temperatureLevel: temperatureLevel ?? this.temperatureLevel,
      perfume: perfume ?? this.perfume,
      scentLevel: scentLevel ?? this.scentLevel,
      ambientLight: ambientLight ?? this.ambientLight,
      seatPosition: seatPosition ?? this.seatPosition,
      seatIncline: seatIncline ?? this.seatIncline,
      chargerUsb: chargerUsb ?? this.chargerUsb,
      wifi: wifi ?? this.wifi,
      water: water ?? this.water,
      snacks: snacks ?? this.snacks,
      smokeFree: smokeFree ?? this.smokeFree,
      disinfected: disinfected ?? this.disinfected,
      silentRide: silentRide ?? this.silentRide,
      pets: pets ?? this.pets,
      drivingStyle: drivingStyle ?? this.drivingStyle,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      suspension: suspension ?? this.suspension,
      vehicleType: vehicleType ?? this.vehicleType,
      interiorColor: interiorColor ?? this.interiorColor,
      brands: brands ?? (this.brands == null ? null : List.of(this.brands!)),
      preferredDriver: preferredDriver ?? this.preferredDriver,
      helmetType: helmetType ?? this.helmetType,
      helmetHygiene: helmetHygiene ?? this.helmetHygiene,
      protections: protections ?? this.protections,
      motoSpeed: motoSpeed ?? this.motoSpeed,
      intercom: intercom ?? this.intercom,
      energyType: energyType ?? this.energyType,
      carbonOffset: carbonOffset ?? this.carbonOffset,
      engineSilence: engineSilence ?? this.engineSilence,
      paymentMode: paymentMode ?? this.paymentMode,
      invoiceMethod: invoiceMethod ?? this.invoiceMethod,
      notifications: notifications ?? this.notifications,
    );
  }

  Map<String, dynamic> toMap() => {
        'ambiance': ambiance,
        'music': music,
        'musicStyle': musicStyle,
        'conversation': conversation,
        'temperature': temperature,
        'temperatureLevel': temperatureLevel,
        'perfume': perfume,
        'scentLevel': scentLevel,
        'ambientLight': ambientLight,
        'seatPosition': seatPosition,
        'seatIncline': seatIncline,
        'chargerUsb': chargerUsb,
        'wifi': wifi,
        'water': water,
        'snacks': snacks,
        'smokeFree': smokeFree,
        'disinfected': disinfected,
        'silentRide': silentRide,
        'pets': pets,
        'drivingStyle': drivingStyle,
        'avgSpeed': avgSpeed,
        'suspension': suspension,
        'vehicleType': vehicleType,
        'interiorColor': interiorColor,
        'brands': brands,
        'preferredDriver': preferredDriver,
        'helmetType': helmetType,
        'helmetHygiene': helmetHygiene,
        'protections': protections,
        'motoSpeed': motoSpeed,
        'intercom': intercom,
        'energyType': energyType,
        'carbonOffset': carbonOffset,
        'engineSilence': engineSilence,
        'paymentMode': paymentMode,
        'invoiceMethod': invoiceMethod,
        'notifications': notifications,
      };

  factory PassengerPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) return PassengerPreferences();
    List<String>? _safeStringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
      return null;
    }

    return PassengerPreferences(
      ambiance: (map['ambiance'] ?? "Libre").toString(),
      music: (map['music'] is bool) ? map['music'] as bool : true,
      musicStyle: map['musicStyle']?.toString() ?? "Chill",
      conversation: map['conversation']?.toString() ?? "Libre",
      temperature:
          (map['temperature'] is bool) ? map['temperature'] as bool : false,
      temperatureLevel: map['temperatureLevel']?.toString(),
      perfume: (map['perfume'] is bool) ? map['perfume'] as bool : false,
      scentLevel: map['scentLevel']?.toString(),
      ambientLight: map['ambientLight']?.toString(),
      seatPosition: map['seatPosition']?.toString(),
      seatIncline: map['seatIncline']?.toString(),
      chargerUsb: map['chargerUsb']?.toString(),
      wifi: (map['wifi'] is bool) ? map['wifi'] as bool : false,
      water: map['water']?.toString(),
      snacks: map['snacks']?.toString(),
      smokeFree: (map['smokeFree'] is bool) ? map['smokeFree'] as bool : true,
      disinfected:
          map['disinfected'] is bool ? map['disinfected'] as bool : null,
      silentRide: map['silentRide'] is bool ? map['silentRide'] as bool : null,
      pets: (map['pets'] is bool) ? map['pets'] as bool : false,
      drivingStyle: map['drivingStyle']?.toString(),
      avgSpeed: map['avgSpeed']?.toString(),
      suspension: map['suspension']?.toString(),
      vehicleType: map['vehicleType']?.toString() ?? "Berline",
      interiorColor: map['interiorColor']?.toString() ?? "Noir",
      brands: _safeStringList(map['brands']),
      preferredDriver: map['preferredDriver'] is bool
          ? map['preferredDriver'] as bool
          : null,
      helmetType: map['helmetType']?.toString(),
      helmetHygiene: map['helmetHygiene']?.toString(),
      protections: map['protections']?.toString(),
      motoSpeed: map['motoSpeed']?.toString(),
      intercom: map['intercom'] is bool ? map['intercom'] as bool : null,
      energyType: map['energyType']?.toString() ?? "Électrique",
      carbonOffset:
          map['carbonOffset'] is bool ? map['carbonOffset'] as bool : null,
      engineSilence:
          map['engineSilence'] is bool ? map['engineSilence'] as bool : null,
      paymentMode: map['paymentMode']?.toString() ?? "Automatique",
      invoiceMethod: map['invoiceMethod']?.toString() ?? "Email",
      notifications: map['notifications']?.toString() ?? "Push",
    );
  }
}
