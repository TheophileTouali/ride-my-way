import 'package:equatable/equatable.dart';

class DriverUser extends Equatable {
  // 🔑 Identité
  final String uid;

  // ⚠️ Apple directive : TOUT optionnel sauf uid
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;

  // 👤 Profil
  final String? photoUrl;
  final String? address;
  final String? birthdate;

  // 🚗 Véhicule
  final String? vehicleType;
  final String? vehicleBrand;
  final String? vehicleModel;
  final String? vehicleYear;
  final String? licensePlate;
  final String? driverLicenseNumber;
  final String? vehiclePhotoUrl;

  // 📂 Documents
  final Map<String, dynamic> documents;

  const DriverUser({
    required this.uid,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.photoUrl,
    this.address,
    this.birthdate,
    this.vehicleType,
    this.vehicleBrand,
    this.vehicleModel,
    this.vehicleYear,
    this.licensePlate,
    this.driverLicenseNumber,
    this.vehiclePhotoUrl,
    this.documents = const {},
  });

  // 🧠 Helpers sûrs
  String get fullName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    final full = ('$fn $ln').trim();
    return full.isEmpty ? 'Chauffeur' : full;
  }

  String? get idCardUrl => documents['idCard'] as String?;
  String? get insuranceUrl => documents['insurance'] as String?;
  String? get registrationUrl => documents['registration'] as String?;
  String? get driverLicenseUrl => documents['driverLicense'] as String?;

  // 🔄 Factory Firestore SAFE
  factory DriverUser.fromMap(Map<String, dynamic> map, {required String uid}) {
    String? _str(dynamic v) {
      if (v == null) return null;
      if (v is String) {
        final s = v.trim();
        return s.isEmpty ? null : s;
      }
      return v.toString();
    }

    Map<String, dynamic> _map(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return <String, dynamic>{};
    }

    return DriverUser(
      uid: uid,
      firstName: _str(map['firstName']),
      lastName: _str(map['lastName']),
      email: _str(map['email']),
      phone: _str(map['phone']),
      photoUrl: _str(map['photoUrl']),
      address: _str(map['address']),
      birthdate: _str(map['birthdate']),
      vehicleType: _str(map['vehicleType']),
      vehicleBrand:
          _str(map['vehicleBrand']) ?? _str(map['carBrand']), // compat ancien
      vehicleModel: _str(map['vehicleModel']),
      vehicleYear: _str(map['vehicleYear']),
      licensePlate: _str(map['licensePlate']),
      driverLicenseNumber: _str(map['driverLicenseNumber']),
      vehiclePhotoUrl: _str(map['vehiclePhotoUrl']),
      documents: _map(map['documents']),
    );
  }

  // 🔄 Firestore write CLEAN
  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'address': address,
      'birthdate': birthdate,
      'vehicleType': vehicleType,
      'vehicleBrand': vehicleBrand, // ✅ standardisé
      'vehicleModel': vehicleModel,
      'vehicleYear': vehicleYear,
      'licensePlate': licensePlate,
      'driverLicenseNumber': driverLicenseNumber,
      'vehiclePhotoUrl': vehiclePhotoUrl,
      'documents': documents,
    }..removeWhere((_, v) => v == null);
  }

  Map<String, dynamic> toJson() => toMap();

  @override
  List<Object?> get props => [
        uid,
        firstName,
        lastName,
        email,
        phone,
        photoUrl,
        address,
        birthdate,
        vehicleType,
        vehicleBrand,
        vehicleModel,
        vehicleYear,
        licensePlate,
        driverLicenseNumber,
        vehiclePhotoUrl,
        documents,
      ];
}
