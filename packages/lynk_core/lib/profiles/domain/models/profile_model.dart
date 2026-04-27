class ProfileModel {
  final String id;
  final String? email;
  final String? avatarUrl;
  final String userName;
  final String? fullName;
  final String? bio;
  final String? tagline;
  final String? countryCode; // ISO 3166-1 alpha-2
  final String subscriptionTier; // 'free' or 'pro'
  final String verificationStatus; // 'none', 'verified', 'official'

  ProfileModel({
    required this.id,
    this.email,
    this.avatarUrl,
    required this.userName,
    this.fullName,
    this.bio,
    this.tagline,
    this.countryCode,
    required this.subscriptionTier,
    required this.verificationStatus,
  });

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    final info = map['info'] as Map<String, dynamic>? ?? {};
    return ProfileModel(
      id: map['id'] as String,
      email: map['email'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      userName: map['user_name'] as String? ?? 'user',
      fullName: map['full_name'] as String?,
      bio: info['bio'] as String?,
      tagline: info['tagline'] as String?,
      countryCode: map['country_code'] as String?,
      subscriptionTier: (map['is_premium'] == true) ? 'pro' : 'free',
      verificationStatus: (map['is_verified'] == true) ? 'verified' : 'none',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'full_name': fullName,
      'user_name': userName,
      'avatar_url': avatarUrl,
      'country_code': countryCode,
      'info': {
        'bio': bio,
        'tagline': tagline,
      },
    };
  }

  bool get isIncomplete => fullName == null || fullName!.isEmpty;
  bool get isPremium => subscriptionTier == 'pro';

  ProfileModel copyWith({
    String? fullName,
    String? userName,
    String? bio,
    String? tagline,
    String? avatarUrl,
    String? countryCode,
  }) {
    return ProfileModel(
      id: id,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      userName: userName ?? this.userName,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      tagline: tagline ?? this.tagline,
      countryCode: countryCode ?? this.countryCode,
      subscriptionTier: subscriptionTier,
      verificationStatus: verificationStatus,
    );
  }
}
