import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import 'auth_screen.dart';
import 'queue_screen.dart';
import 'tenant_setup_screen.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final AuthProvider _auth;
  late final TenantProvider _tenants;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _tenants = context.read<TenantProvider>();
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final user = _auth.user;
    if (user == null) {
      if (_loadedFor != null) {
        _tenants.clear();
        _loadedFor = null;
      }
      return;
    }
    if (_loadedFor != user.id) {
      _loadedFor = user.id;
      _tenants.loadForUser(user.id);
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tenants = context.watch<TenantProvider>();

    switch (auth.status) {
      case AuthStatus.initial:
        return const _Splash(message: 'Restoring your session...');
      case AuthStatus.unauthenticated:
        return const AuthScreen();
      case AuthStatus.authenticated:
        if (tenants.isLoading && tenants.tenants.isEmpty) {
          return const _Splash(message: 'Loading workspaces...');
        }
        if (tenants.errorMessage != null && tenants.tenants.isEmpty) {
          return _TenantError(
            message: tenants.errorMessage!,
            onRetry: () => _tenants.loadForUser(auth.user!.id),
          );
        }
        final tenant = tenants.activeTenant;
        if (tenant == null) {
          return const TenantSetupScreen();
        }
        return QueueScreen(
          key: ValueKey('${auth.user!.id}:${tenant.id}'),
          ownerId: auth.user!.id,
          tenantId: tenant.id,
          tenantName: tenant.name,
          userEmail: auth.user!.label,
        );
    }
  }
}

class _Splash extends StatelessWidget {
  final String message;

  const _Splash({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _TenantError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _TenantError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              Text(message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
