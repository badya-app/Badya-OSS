import 'package:Badya/services/user_search_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSearchService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late UserSearchService service;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      service = UserSearchService(firestore: fakeFirestore);

      // Seed two users with display_name_lowercase for prefix search tests.
      await fakeFirestore.collection('users').doc('u1').set({
        'display_name': 'Alice Wonder',
        'display_name_lowercase': 'alice wonder',
      });
      await fakeFirestore.collection('users').doc('u2').set({
        'display_name': 'Bob Builder',
        'display_name_lowercase': 'bob builder',
      });
    });

    test('normalizeUsername lowercases and trims input', () {
      expect(service.normalizeUsername('  Alice_123  '), 'alice_123');
    });

    test('claimUsername enforces length and character constraints', () async {
      // Too short
      expect(
        () => service.claimUsername('u1', 'ab'),
        throwsA(isA<Exception>()),
      );

      // Invalid characters
      expect(
        () => service.claimUsername('u1', 'Bad*Name'),
        throwsA(isA<Exception>()),
      );

      // Valid username should succeed.
      await service.claimUsername('u1', 'alice_01');

      final mapping = await fakeFirestore
          .collection('usernames')
          .doc('alice_01')
          .get();
      final userDoc =
          await fakeFirestore.collection('users').doc('u1').get();

      expect(mapping.exists, true);
      expect(mapping.data()!['uid'], 'u1');
      expect(userDoc.data()!['username'], 'alice_01');
    });

    test('claimUsername prevents two different users from sharing username',
        () async {
      await service.claimUsername('u1', 'shared_name');

      // Second user trying to take the same username should fail.
      expect(
        () => service.claimUsername('u2', 'shared_name'),
        throwsA(isA<Exception>()),
      );
    });

    test('findByUsername returns user document for valid mapping', () async {
      await service.claimUsername('u1', 'alice_handle');

      final userDoc = await service.findByUsername('alice_handle');

      expect(userDoc, isNotNull);
      expect(userDoc!.id, 'u1');
    });

    test('searchByDisplayNamePrefix filters by lowercase prefix', () async {
      final result = await service.searchByDisplayNamePrefix('ali');

      expect(result.docs.length, 1);
      expect(result.docs.first.id, 'u1');

      final emptyResult =
          await service.searchByDisplayNamePrefix('');
      expect(emptyResult.docs.length, 0);
    });
  });
}


