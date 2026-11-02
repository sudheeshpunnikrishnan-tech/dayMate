import 'package:flutter/material.dart';

void main() {
  runApp(const DayMateApp());
}

class DayMateApp extends StatelessWidget {
  const DayMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dayMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('dayMate')),
      body: const Center(
        child: Text(
          'Welcome to dayMate!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
