import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for username uniqueness and basic user search.
class UserSearchService {
  final FirebaseFirestore? _firestore;

  UserSearchService({FirebaseFirestore? firestore})
    : _firestore = LocalMode.enabled
          ? firestore
          : (firestore ?? FirebaseFirestore.instance);

  /// Normalize a username to the allowed format (lowercase).
  String normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }

  /// Attempt to claim a unique username for a user.
  ///
  /// Uses a transaction on `usernames/{username}` and the user doc to ensure
  /// only one user can own a given username.
  Future<void> claimUsername(String userId, String rawUsername) async {
    final username = normalizeUsername(rawUsername);
    if (username.length < 3 || username.length > 20) {
      throw Exception('Username must be between 3 and 20 characters.');
    }
    final usernameRegExp = RegExp(r'^[a-z0-9_]+$');
    if (!usernameRegExp.hasMatch(username)) {
      throw Exception(
        'Username can only contain lowercase letters, numbers, and underscores.',
      );
    }

    final usernameRef = _firestore.collection('usernames').doc(username);
    final userRef = _firestore.collection('users').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final usernameSnap = await transaction.get(usernameRef);
      final userSnap = await transaction.get(userRef);

      if (!userSnap.exists) {
        throw Exception('User document not found');
      }

      // If username doc exists and is owned by a different user → conflict.
      if (usernameSnap.exists) {
        final data = usernameSnap.data() as Map<String, dynamic>;
        final existingOwner = data['uid'] as String?;
        if (existingOwner != null && existingOwner != userId) {
          throw Exception('Username is already taken');
        }
      }

      // Write / overwrite username mapping
      transaction.set(usernameRef, {
        'uid': userId,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Update username field on user document
      transaction.update(userRef, {'username': username});
    });
  }

  /// Look up a user by exact username.
  Future<DocumentSnapshot<Map<String, dynamic>>?> findByUsername(
    String rawUsername,
  ) async {
    final username = normalizeUsername(rawUsername);
    final mapping = await _firestore
        .collection('usernames')
        .doc(username)
        .get();
    if (!mapping.exists || mapping.data() == null) return null;
    final uid = mapping.data()!['uid'] as String?;
    if (uid == null) return null;
    final userDoc = await _firestore.collection('users').doc(uid).get();
    return userDoc.exists ? userDoc : null;
  }

  /// Search users by display name prefix (case-insensitive, simple range query).
  ///
  /// WARNING: This relies on a `display_name_lowercase` field being maintained
  /// on user documents for efficient querying.
  Future<QuerySnapshot<Map<String, dynamic>>> searchByDisplayNamePrefix(
    String query, {
    int limit = 20,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      // Return an empty query when the search text is empty.
      return _firestore
          .collection('users')
          .where('display_name_lowercase', isEqualTo: '__no_match__')
          .limit(0)
          .get();
    }

    final end = '$q\uf8ff';
    return _firestore
        .collection('users')
        .where('display_name_lowercase', isGreaterThanOrEqualTo: q)
        .where('display_name_lowercase', isLessThanOrEqualTo: end)
        .limit(limit)
        .get();
  }
}
