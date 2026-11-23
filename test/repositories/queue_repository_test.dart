import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tp7/models/client.dart';
import 'package:tp7/repositories/queue_repository.dart';

class MockQueueRemoteDataSource extends Mock
    implements QueueRemoteDataSource {}

void main() {
  late MockQueueRemoteDataSource dataSource;
  late QueueRepository repository;

  final sampleClient = Client(
    id: 'abc',
    name: 'Alice',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    dataSource = MockQueueRemoteDataSource();
    repository = QueueRepository(dataSource);
  });

  test('fetchPage delegates to the remote data source', () async {
    when(() => dataSource.fetchPage(offset: 0, limit: 20))
        .thenAnswer((_) async => [sampleClient]);

    final result = await repository.fetchPage(offset: 0, limit: 20);

    expect(result, equals([sampleClient]));
    verify(() => dataSource.fetchPage(offset: 0, limit: 20)).called(1);
  });

  test('registerOnServer delegates to the remote data source', () async {
    when(() => dataSource.registerOnServer(sampleClient))
        .thenAnswer((_) async => sampleClient);

    final result = await repository.registerOnServer(sampleClient);

    expect(result, equals(sampleClient));
    verify(() => dataSource.registerOnServer(sampleClient)).called(1);
  });

  test('insertEvents delegates to the remote data source', () {
    final stream = Stream<Client>.empty();
    when(() => dataSource.insertEvents()).thenAnswer((_) => stream);

    expect(repository.insertEvents(), same(stream));
  });
}
