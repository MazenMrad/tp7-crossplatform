import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tp7/models/app_user.dart';
import 'package:tp7/providers/auth_provider.dart';
import 'package:tp7/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService service;
  late StreamController<AppUser?> controller;
  late AuthProvider provider;

  final user = AppUser(id: 'u1', email: 'alice@example.com');

  setUp(() {
    service = MockAuthService();
    controller = StreamController<AppUser?>.broadcast();
    when(() => service.authStateChanges).thenAnswer((_) => controller.stream);
    when(() => service.currentUser).thenReturn(null);
    when(
      () => service.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => service.signUp(
        email: any(named: 'email'),
        password: any(named: 'password'),
        displayName: any(named: 'displayName'),
      ),
    ).thenAnswer((_) async {});
    when(() => service.signOut()).thenAnswer((_) async {});
    provider = AuthProvider(service);
  });

  tearDown(() async {
    provider.dispose();
    await controller.close();
  });

  test('starts unauthenticated when there is no stored session', () async {
    await provider.initialize();

    expect(provider.status, equals(AuthStatus.unauthenticated));
    expect(provider.user, isNull);
  });

  test('restores the current user on initialize', () async {
    when(() => service.currentUser).thenReturn(user);

    await provider.initialize();

    expect(provider.status, equals(AuthStatus.authenticated));
    expect(provider.user, equals(user));
  });

  test('follows auth state changes', () async {
    await provider.initialize();

    controller.add(user);
    await Future<void>.delayed(Duration.zero);
    expect(provider.isAuthenticated, isTrue);
    expect(provider.user, equals(user));

    controller.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(provider.status, equals(AuthStatus.unauthenticated));
  });

  test('signIn reports failure and exposes an error message', () async {
    await provider.initialize();
    when(
      () => service.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(Exception('Invalid credentials'));

    final success = await provider.signIn(
      email: 'alice@example.com',
      password: 'wrong',
    );

    expect(success, isFalse);
    expect(provider.errorMessage, contains('Invalid credentials'));
    expect(provider.isBusy, isFalse);
  });

  test('signUp forwards the display name', () async {
    await provider.initialize();

    final success = await provider.signUp(
      email: 'alice@example.com',
      password: 'secret123',
      displayName: 'Alice',
    );

    expect(success, isTrue);
    verify(
      () => service.signUp(
        email: 'alice@example.com',
        password: 'secret123',
        displayName: 'Alice',
      ),
    ).called(1);
  });

  test('signOut clears the user', () async {
    when(() => service.currentUser).thenReturn(user);
    await provider.initialize();

    await provider.signOut();

    expect(provider.user, isNull);
    expect(provider.status, equals(AuthStatus.unauthenticated));
    verify(() => service.signOut()).called(1);
  });
}
