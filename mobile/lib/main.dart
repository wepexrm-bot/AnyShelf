import 'package:flutter/material.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(const CloudReadApp());
}

class CloudReadApp extends StatelessWidget {
  const CloudReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CloudRead',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const LibraryScreen(),
    );
  }
}
