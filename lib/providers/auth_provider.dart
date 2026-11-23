import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';

enum AuthStatus { initial, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _service;
  StreamSubscription<AppUser?>? _subscription;

  AuthStatus _status = AuthStatus.initial;
  AppUser? _user;
  String? _errorMessage;
  bool _isBusy = false;
  bool _disposed = false;

  AuthProvider(this._service);

  AuthStatus get status => _status;
  AppUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _isBusy;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> initialize() async {
    _subscription = _service.authStateChanges.listen(_applyUser);
    _applyUser(_service.currentUser);
    _notify();
  }

  void _applyUser(AppUser? user) {
    _user = user;
    _status = user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    return _run(() => _service.signIn(email: email, password: password));
  }

  Future<bool> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return _run(
      () => _service.signUp(
        email: email,
        password: password,
        displayName: displayName,
      ),
    );
  }

  Future<void> signOut() async {
    try {
      await _service.signOut();
      _applyUser(null);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Could not sign out. Please try again.';
      debugPrint('signOut failed: $e');
    } finally {
      _notify();
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    _notify();
    try {
      await action();
      return true;
    } catch (e) {
      debugPrint('authentication failed: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      if (_errorMessage == null || _errorMessage!.trim().isEmpty) {
        _errorMessage = 'Authentication failed';
      }
      return false;
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
