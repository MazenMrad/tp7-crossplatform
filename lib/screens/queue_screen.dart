import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/queue_state.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/queue_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/client_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/offline_banner.dart';
import '../widgets/queue_empty_widget.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    this.ownerId,
    this.tenantId,
    this.tenantName,
    this.userEmail,
  });

  final String? ownerId;
  final String? tenantId;
  final String? tenantName;
  final String? userEmail;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  late final ConnectivityProvider _connectivityProvider;

  @override
  void initState() {
    super.initState();
    _connectivityProvider = context.read<ConnectivityProvider>();
    _connectivityProvider.addListener(_onConnectivityChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final queue = context.read<QueueProvider>();
      final ownerId = widget.ownerId;
      final tenantId = widget.tenantId;
      if (ownerId != null && tenantId != null) {
        queue.setContext(ownerId: ownerId, tenantId: tenantId);
      }
      queue.fetchInitialQueue();
      queue.subscribeToRealtime();
    });
  }

  @override
  void dispose() {
    _connectivityProvider.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (_connectivityProvider.isOnline) {
      context.read<QueueProvider>().syncPending();
    }
  }

  Future<void> _showRegisterDialog() async {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join the waiting queue'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Your name'),
            validator: (value) =>
                (value == null || value.trim().isEmpty)
                    ? 'Please enter your name'
                    : null,
            onFieldSubmitted: (value) {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(nameController.text.trim());
              }
            },
            child: const Text('Join queue'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    await context.read<QueueProvider>().registerClient(name);
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityProvider>();
    final queue = context.watch<QueueProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Waiting Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: queue.fetchInitialQueue,
          ),
          if (widget.tenantId != null) _buildWorkspaceMenu(),
          if (widget.userEmail != null) _buildAccountMenu(),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(status: connectivity.status),
          Expanded(child: _buildBody(queue)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRegisterDialog,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildWorkspaceMenu() {
    final tenants = context.watch<TenantProvider>();
    return PopupMenuButton<String>(
      tooltip: 'Switch workspace',
      onSelected: tenants.selectTenant,
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('Workspace'),
        ),
        ...tenants.tenants.map(
          (tenant) => PopupMenuItem<String>(
            value: tenant.id,
            child: Row(
              children: [
                Icon(
                  tenant.id == widget.tenantId
                      ? Icons.check
                      : Icons.space_dashboard_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(tenant.name)),
              ],
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.business_outlined, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                widget.tenantName ?? 'Workspace',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        if (value == 'sign_out') {
          context.read<AuthProvider>().signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(widget.userEmail ?? 'Account'),
        ),
        const PopupMenuItem<String>(
          value: 'sign_out',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 8),
              Text('Sign out'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(QueueProvider queue) {
    switch (queue.state) {
      case QueueState.initial:
      case QueueState.loading:
        return const LoadingWidget(message: 'Loading the waiting queue...');
      case QueueState.empty:
        return const QueueEmptyWidget();
      case QueueState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(queue.errorMessage ?? 'Something went wrong'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: queue.fetchInitialQueue,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case QueueState.loaded:
      case QueueState.refreshing:
      case QueueState.loadingMore:
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200) {
              queue.loadMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: queue.fetchInitialQueue,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: queue.clients.length + (queue.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= queue.clients.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LoadingWidget(message: 'Loading more...'),
                  );
                }
                return ClientCard(client: queue.clients[index]);
              },
            ),
          ),
        );
    }
  }
}
