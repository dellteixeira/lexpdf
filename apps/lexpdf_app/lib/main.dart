import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/core/storage/local_database.dart';
import 'src/lexpdf_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  final supportDirectory = await getApplicationSupportDirectory();
  await supportDirectory.create(recursive: true);
  final databasePath =
      '${supportDirectory.path}${Platform.pathSeparator}lexpdf.sqlite3';
  final database = LocalDatabase.open(databasePath);

  runApp(LexPdfApp(database: database));
}
