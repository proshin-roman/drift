import 'package:migrations_example/database.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';
import 'package:drift_dev/api/migrations.dart';

// Import the generated schema helper to instantiate databases at old versions.
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('upgrade from v1 to v2', () async {
    final schema = await verifier.schemaAt(1);

    // Add some data to the users table, which only has an id column at v1
    final oldDb = v1.DatabaseAtV1.connect(schema.newConnection());
    await oldDb.into(oldDb.users).insert(const v1.UsersCompanion(id: Value(1)));
    await oldDb.close();

    // Run the migration and verify that it adds the name column.
    final db = Database(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    await db.close();

    // Make sure the user is still here
    final migratedDb = v2.DatabaseAtV2.connect(schema.newConnection());
    final user = await migratedDb.select(migratedDb.users).getSingle();
    expect(user.id, 1);
    expect(user.name, 'no name'); // default from the migration
    await migratedDb.close();
  });

  test('upgrade from v2 to v3', () async {
    final connection = await verifier.startAt(2);
    final db = Database(connection);

    await verifier.migrateAndValidate(db, 3);
    await db.close();
  });

  test('upgrade from v3 to v4', () async {
    final connection = await verifier.startAt(3);
    final db = Database(connection);

    await verifier.migrateAndValidate(db, 4);
    await db.close();
  });

  test('upgrade from v4 to v5', () async {
    final connection = await verifier.startAt(4);
    final db = Database(connection);

    await verifier.migrateAndValidate(db, 5);
    await db.close();
  });

  test('view works after upgrade from v4 to v5', () async {
    final schema = await verifier.schemaAt(4);

    final oldDb = v4.DatabaseAtV4.connect(schema.newConnection());
    await oldDb.batch((batch) {
      batch
        ..insert(oldDb.users, v4.UsersCompanion.insert(id: Value(1)))
        ..insert(oldDb.users, v4.UsersCompanion.insert(id: Value(2)))
        ..insert(
            oldDb.groups, v4.GroupsCompanion.insert(title: 'Test', owner: 1));
    });
    await oldDb.close();

    // Run the migration and verify that it adds the view.
    final db = Database(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    await db.close();

    // Make sure the view works!
    final migratedDb = v5.DatabaseAtV5.connect(schema.newConnection());
    final viewCount = await migratedDb.select(migratedDb.groupCount).get();

    expect(
        viewCount,
        contains(isA<v5.GroupCountData>()
            .having((e) => e.id, 'id', 1)
            .having((e) => e.groupCount, 'groupCount', 1)));
    expect(
        viewCount,
        contains(isA<v5.GroupCountData>()
            .having((e) => e.id, 'id', 2)
            .having((e) => e.groupCount, 'groupCount', 0)));
    await migratedDb.close();
  });
}
