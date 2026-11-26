import 'package:Badya/services/block_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlockService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late BlockService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = BlockService(firestore: fakeFirestore);
    });

    test('blockUser stores a doc under users/{uid}/blocked', () async {
      await service.blockUser(
        currentUserId: 'me',
        blockedUid: 'them',
        displayName: 'Them User',
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc('me')
          .collection('blocked')
          .doc('them')
          .get();

      expect(doc.exists, true);
      expect(doc.data()!['display_name'], 'Them User');
      expect(doc.data()!['blocked_uid'], 'them');
    });

    test('blockUser ignores blocking yourself', () async {
      await service.blockUser(currentUserId: 'me', blockedUid: 'me');

      final snap = await fakeFirestore
          .collection('users')
          .doc('me')
          .collection('blocked')
          .get();
      expect(snap.docs, isEmpty);
    });

    test('isBlocked reflects block state', () async {
      expect(
        await service.isBlocked(currentUserId: 'me', blockedUid: 'them'),
        false,
      );

      await service.blockUser(currentUserId: 'me', blockedUid: 'them');

      expect(
        await service.isBlocked(currentUserId: 'me', blockedUid: 'them'),
        true,
      );
    });

    test('unblockUser removes the doc', () async {
      await service.blockUser(currentUserId: 'me', blockedUid: 'them');
      await service.unblockUser(
        currentUserId: 'me',
        blockedUid: 'them',
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc('me')
          .collection('blocked')
          .doc('them')
          .get();
      expect(doc.exists, false);
    });

    test('getBlockedUids returns only the blocker\'s blocked uids', () async {
      await service.blockUser(currentUserId: 'me', blockedUid: 'u1');
      await service.blockUser(currentUserId: 'me', blockedUid: 'u2');
      await service.blockUser(currentUserId: 'other', blockedUid: 'u3');

      final uids = await service.getBlockedUids('me');
      expect(uids, {'u1', 'u2'});
    });

    test('filterByBlocked drops items from blocked authors', () {
      final items = [
        {'author': 'u1'},
        {'author': 'u2'},
        {'author': 'u3'},
      ];

      final filtered = BlockService.filterByBlocked(
        items,
        {'u2'},
        (item) => item['author'] as String,
      ).toList();

      expect(filtered.length, 2);
      expect(filtered.map((i) => i['author']), ['u1', 'u3']);
    });

    test('filterByBlocked returns everything when block list is empty', () {
      final items = [{'author': 'u1'}, {'author': 'u2'}];
      final filtered = BlockService.filterByBlocked(
        items,
        const {},
        (item) => item['author'] as String,
      ).toList();
      expect(filtered.length, 2);
    });
  });
}
