class PassengerPreferences {
  String ambiance;
  bool music;
  bool perfume;
  bool temperature;
  bool wifi;
  bool smokeFree;
  bool pets;

  PassengerPreferences({
    required this.ambiance,
    required this.music,
    required this.perfume,
    required this.temperature,
    required this.wifi,
    required this.smokeFree,
    required this.pets,
  });

  PassengerPreferences copyWith({
    String? ambiance,
    bool? music,
    bool? perfume,
    bool? temperature,
    bool? wifi,
    bool? smokeFree,
    bool? pets,
  }) {
    return PassengerPreferences(
      ambiance: ambiance ?? this.ambiance,
      music: music ?? this.music,
      perfume: perfume ?? this.perfume,
      temperature: temperature ?? this.temperature,
      wifi: wifi ?? this.wifi,
      smokeFree: smokeFree ?? this.smokeFree,
      pets: pets ?? this.pets,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ambiance': ambiance,
      'music': music,
      'perfume': perfume,
      'temperature': temperature,
      'wifi': wifi,
      'smokeFree': smokeFree,
      'pets': pets,
    };
  }

  factory PassengerPreferences.fromMap(Map<String, dynamic> map) {
    return PassengerPreferences(
      ambiance: map['ambiance'] ?? '',
      music: map['music'] ?? false,
      perfume: map['perfume'] ?? false,
      temperature: map['temperature'] ?? false,
      wifi: map['wifi'] ?? false,
      smokeFree: map['smokeFree'] ?? false,
      pets: map['pets'] ?? false,
    );
  }
}
