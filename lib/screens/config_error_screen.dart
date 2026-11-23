import 'package:flutter/material.dart';

class ConfigErrorScreen extends StatelessWidget {
  const ConfigErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.settings_suggest, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Missing Supabase configuration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'The app was launched without SUPABASE_URL and '
                'SUPABASE_ANON_KEY. Start it with:',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey.shade200,
                child: const SelectableText(
                  'flutter run \\\n'
                  '  --dart-define=SUPABASE_URL=https://qrvpcueshhmofherertv.supabase.co \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=sb_publishable_CJPh-Gp0-F3Fc7RKiEKbWQ_-drQQvYn',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'From VS Code, use the "tp7 (Android)" or "tp7 (Windows)" '
                'launch profile (F5), which passes these values already.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
