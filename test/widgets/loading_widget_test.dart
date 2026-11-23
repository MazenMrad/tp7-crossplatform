import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp7/widgets/loading_widget.dart';
import 'package:tp7/widgets/queue_empty_widget.dart';

void main() {
  testWidgets('LoadingWidget shows a default message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoadingWidget())),
    );

    expect(find.text('Loading...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('LoadingWidget shows a custom message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LoadingWidget(message: 'Syncing...')),
      ),
    );

    expect(find.text('Syncing...'), findsOneWidget);
  });

  testWidgets('QueueEmptyWidget explains that the queue is empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QueueEmptyWidget())),
    );

    expect(find.text('The waiting queue is empty'), findsOneWidget);
    expect(find.text('New registrations will appear here.'), findsOneWidget);
  });
}
