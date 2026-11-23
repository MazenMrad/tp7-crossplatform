import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/queue_provider.dart';
import 'providers/tenant_provider.dart';
import 'repositories/queue_repository.dart';
import 'screens/config_error_screen.dart';
import 'screens/session_gate.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/geolocation_service.dart';
import 'services/supabase_auth_service.dart';
import 'services/supabase_tenant_service.dart';
import 'services/sync_service.dart';
import 'services/tenant_service.dart';
import 'storage/local_queue_storage.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: _supabaseAnonKey,
    );
  }

  runApp(const Tp7App());
}

class Tp7App extends StatelessWidget {
  const Tp7App({super.key});

  static bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!Tp7App.isConfigured) {
      return const MaterialApp(home: ConfigErrorScreen());
    }

    final supabase = Supabase.instance.client;

    return MultiProvider(
      providers: [
        Provider<ConnectivityService>(
          create: (_) => ConnectivityService(supabase),
        ),
        Provider<LocalQueueStorage>(create: (_) => LocalQueueStorage()),
        Provider<GeolocationService>(create: (_) => GeolocationService()),
        Provider<QueueRemoteDataSource>(
          create: (_) => SupabaseQueueRemoteDataSource(supabase),
        ),
        Provider<QueueRepository>(
          create: (context) => QueueRepository(
            context.read<QueueRemoteDataSource>(),
          ),
        ),
        Provider<SyncService>(
          create: (context) => SyncService(
            context.read<LocalQueueStorage>(),
            context.read<QueueRepository>(),
          ),
        ),
        Provider<AuthService>(
          create: (_) => SupabaseAuthService(supabase),
        ),
        Provider<TenantService>(
          create: (_) => SupabaseTenantService(supabase),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthProvider(context.read<AuthService>())
            ..initialize(),
        ),
        ChangeNotifierProvider(
          create: (context) => TenantProvider(context.read<TenantService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ConnectivityProvider(
            context.read<ConnectivityService>(),
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (context) => QueueProvider(
            context.read<QueueRepository>(),
            context.read<GeolocationService>(),
            context.read<LocalQueueStorage>(),
            context.read<SyncService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Waiting Room',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const SessionGate(),
      ),
    );
  }
}
