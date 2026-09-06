import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

class LexPdfApp extends StatelessWidget {
  const LexPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LexPDF',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF246BFD),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6EA0FF),
        brightness: Brightness.dark,
      ),
      home: const LibraryScreen(),
    );
  }
}
