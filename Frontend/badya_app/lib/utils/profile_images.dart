import 'dart:math';
import 'package:flutter/material.dart';

/// All available profile avatar images bundled in `assets/profile/`.
const List<String> kProfileImages = [
  'assets/profile/profile1.png',
  'assets/profile/profile2.png',
  'assets/profile/profile3.png',
  'assets/profile/profile4.png',
  'assets/profile/profile5.png',
  'assets/profile/profile6.png',
  'assets/profile/profile7.png',
  'assets/profile/profile8.png',
  'assets/profile/profile9.png',
  'assets/profile/profile10.png',
  'assets/profile/profile11.png',
  'assets/profile/profile12.png',
  'assets/profile/profile13.png',
  'assets/profile/profile14.png',
  'assets/profile/profile15.png',
  'assets/profile/profile16.png',
  'assets/profile/profile17.png',
];

/// Returns a random profile image asset path from [kProfileImages].
String getRandomProfileImagePath() {
  final index = Random().nextInt(kProfileImages.length);
  return kProfileImages[index];
}

/// Resolves a stored profile URL into the correct [ImageProvider].
///
/// If [photoUrl] is a local asset path (starts with `assets/`), returns an
/// [AssetImage]. Otherwise returns a [NetworkImage] (for user-uploaded photos).
/// Returns the [fallback] if [photoUrl] is null or empty.
ImageProvider resolveProfileImage(String? photoUrl, {ImageProvider fallback = const AssetImage('assets/profile/profile1.png')}) {
  if (photoUrl == null || photoUrl.isEmpty) return fallback;
  if (photoUrl.startsWith('assets/')) return AssetImage(photoUrl);
  return NetworkImage(photoUrl);
}
