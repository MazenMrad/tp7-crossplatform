import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp7/models/client.dart';
import 'package:tp7/models/sync_status.dart';
import 'package:tp7/widgets/client_card.dart';

void main() {
  Widget wrap(ClientCard card) => MaterialApp(
        home: Scaffold(body: card),
      );

  testWidgets('shows the client name and available location', (tester) async {
    final client = Client(
      id: '1',
      name: 'Alice',
      lat: 36.8065,
      lng: 10.1815,
      createdAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    );

    await tester.pumpWidget(wrap(ClientCard(client: client)));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Location available (36.8065, 10.1815)'), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });

  testWidgets('shows a fallback message when location was not captured',
      (tester) async {
    final client = Client(
      id: '2',
      name: 'Bob',
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(wrap(ClientCard(client: client)));

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Location not captured'), findsOneWidget);
    expect(find.byIcon(Icons.location_off), findsOneWidget);
  });
}
