import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/lexpdf_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const LexPdfApp());
}
