class DriverUser {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String? photoUrl;
  final String? address;
  final String? birthdate;
  final String? vehicleType;
  final String? vehicleBrand;
  final String? vehicleModel;
  final String? vehicleYear;
  final String? licensePlate;
  final String? driverLicenseNumber;
  final String? vehiclePhotoUrl;
  final Map<String, dynamic>? documents;

  DriverUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
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
    this.documents,
  });

  String get fullName => '$firstName $lastName';

  String? get idCardUrl => documents?['idCard'];
  String? get insuranceUrl => documents?['insurance'];
  String? get registrationUrl => documents?['registration'];
  String? get driverLicenseUrl => documents?['driverLicense'];

  factory DriverUser.fromMap(Map<String, dynamic> map, {required String uid}) {
    return DriverUser(
      uid: uid,
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      photoUrl: map['photoUrl'],
      address: map['address'],
      birthdate: map['birthdate'],
      vehicleType: map['vehicleType'],
      vehicleBrand: map['carBrand'],
      vehicleModel: map['vehicleModel'],
      vehicleYear: map['vehicleYear'],
      licensePlate: map['licensePlate'],
      driverLicenseNumber: map['driverLicenseNumber'],
      vehiclePhotoUrl: map['vehiclePhotoUrl'],
      documents: map['documents'] != null ? Map<String, dynamic>.from(map['documents']) : null,
    );
  }
}
