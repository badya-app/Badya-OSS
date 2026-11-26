import 'dart:async';

import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for the block-user feature.
///
/// Blocked users are stored as documents in the `users/{uid}/blocked/{blockedUid}`
/// subcollection of the *blocker's* user document. Only the owner can read or
/// write their own block list (enforced by Firestore security rules), so a
/// blocked user can never see who blocked them.
///
/// Each blocked document stores a small snapshot of the blocked user's
/// `display_name` / `photo_url` at block time — reading another user's
/// `users/{userId}` document is not allowed by the security rules, so the
/// snapshot is what the "Blocked users" management page shows.
class BlockService {
  final FirebaseFirestore? _firestore;

  BlockService({FirebaseFirestore? firestore})
    : _firestore = LocalMode.enabled
          ? firestore
          : (firestore ?? FirebaseFirestore.instance);

  CollectionReference<Map<String, dynamic>> _blockedRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('blocked');

  /// Block [blockedUid] on behalf of [currentUserId], storing a display
  /// snapshot so the management page can render without cross-user reads.
  Future<void> blockUser({
    required String currentUserId,
    required String blockedUid,
    String? displayName,
    String? photoUrl,
  }) async {
    if (blockedUid.isEmpty || blockedUid == currentUserId) return;
    await _blockedRef(currentUserId)
        .doc(blockedUid)
        .set({
          'blocked_uid': blockedUid,
          'display_name': displayName ?? '',
          'photo_url': photoUrl ?? '',
          'blocked_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));
  }

  /// Remove [blockedUid] from [currentUserId]'s block list.
  Future<void> unblockUser({
    required String currentUserId,
    required String blockedUid,
  }) async {
    await _blockedRef(currentUserId)
        .doc(blockedUid)
        .delete()
        .timeout(const Duration(seconds: 10));
  }

  /// Whether [currentUserId] has blocked [blockedUid].
  Future<bool> isBlocked({
    required String currentUserId,
    required String blockedUid,
  }) async {
    final doc = await _blockedRef(currentUserId).doc(blockedUid).get();
    return doc.exists;
  }

  /// All uids currently blocked by [currentUserId] (for content filtering).
  Future<Set<String>> getBlockedUids(String currentUserId) async {
    final snapshot = await _blockedRef(currentUserId).get();
    return snapshot.docs.map((d) => d.id).toSet();
  }

  /// Live stream of the blocker's blocked-user documents (management page).
  Stream<QuerySnapshot<Map<String, dynamic>>> getBlockedUsersStream(
    String currentUserId,
  ) {
    return _blockedRef(currentUserId)
        .orderBy('blocked_at', descending: true)
        .snapshots();
  }

  /// Convenience filter: drop content authored by any uid in [blockedUids].
  static Iterable<T> filterByBlocked<T>(
    Iterable<T> items,
    Set<String> blockedUids,
    String Function(T item) authorUidOf,
  ) {
    if (blockedUids.isEmpty) return items;
    return items.where((item) => !blockedUids.contains(authorUidOf(item)));
  }
}
