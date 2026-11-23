import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp7/models/app_connectivity.dart';
import 'package:tp7/widgets/offline_banner.dart';

void main() {
  Widget wrap(OfflineBanner banner) => MaterialApp(
        home: Scaffold(body: banner),
      );

  testWidgets('Offline banner is displayed when offline', (tester) async {
    await tester.pumpWidget(
      wrap(const OfflineBanner(status: AppConnectivity.offline)),
    );

    expect(find.text('No network connection'), findsOneWidget);
  });

  testWidgets('Backend unavailability is displayed with its own message',
      (tester) async {
    await tester.pumpWidget(
      wrap(const OfflineBanner(status: AppConnectivity.backendUnavailable)),
    );

    expect(find.text('Waiting-room server unavailable'), findsOneWidget);
  });

  testWidgets('Checking state is displayed while the backend is probed',
      (tester) async {
    await tester.pumpWidget(
      wrap(const OfflineBanner(status: AppConnectivity.checking)),
    );

    expect(find.text('Checking connection...'), findsOneWidget);
  });

  testWidgets('Nothing is rendered when online', (tester) async {
    await tester.pumpWidget(
      wrap(const OfflineBanner(status: AppConnectivity.online)),
    );

    expect(find.byType(Container), findsNothing);
  });
}
