import 'package:flutter/foundation.dart';

import '../models/tenant.dart';
import '../services/tenant_service.dart';

class TenantProvider extends ChangeNotifier {
  final TenantService _service;

  List<Tenant> _tenants = const [];
  Tenant? _activeTenant;
  String? _currentUserId;
  String? _errorMessage;
  bool _isLoading = false;
  bool _disposed = false;

  TenantProvider(this._service);

  List<Tenant> get tenants => List.unmodifiable(_tenants);
  Tenant? get activeTenant => _activeTenant;
  String? get currentUserId => _currentUserId;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;

  Future<void> loadForUser(String userId) async {
    if (_currentUserId == userId && _tenants.isNotEmpty) return;
    _currentUserId = userId;
    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final tenants = await _service.fetchTenants();
      if (_disposed) return;
      _tenants = tenants;
      if (tenants.isEmpty) {
        _activeTenant = null;
      } else {
        final previousId = _activeTenant?.id;
        _activeTenant = tenants.firstWhere(
          (tenant) => tenant.id == previousId,
          orElse: () => tenants.first,
        );
      }
    } catch (e) {
      debugPrint('loadForUser failed: $e');
      _errorMessage = 'Could not load workspaces';
      _tenants = const [];
      _activeTenant = null;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void selectTenant(String tenantId) {
    final match = _tenants.where((tenant) => tenant.id == tenantId);
    if (match.isEmpty || _activeTenant == match.first) return;
    _activeTenant = match.first;
    _notify();
  }

  Future<bool> createTenant(String name) async {
    if (name.trim().isEmpty) return false;
    _isLoading = true;
    _errorMessage = null;
    _notify();
    try {
      final id = await _service.createTenant(name.trim());
      final tenants = await _service.fetchTenants();
      if (_disposed) return true;
      _tenants = tenants;
      _activeTenant = tenants.firstWhere(
        (tenant) => tenant.id == id,
        orElse: () => tenants.isNotEmpty ? tenants.first : _emptyTenant(id, name),
      );
      return true;
    } catch (e) {
      debugPrint('createTenant failed: $e');
      _errorMessage = 'Could not create the workspace';
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void clear() {
    _tenants = const [];
    _activeTenant = null;
    _currentUserId = null;
    _errorMessage = null;
    _isLoading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Tenant _emptyTenant(String id, String name) => Tenant(
        id: id,
        name: name.trim(),
        role: 'owner',
        createdAt: DateTime.now(),
      );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
