import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KlcNewcomersApp());
}

class KlcNewcomersApp extends StatelessWidget {
  const KlcNewcomersApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF2B3A67); // Deep Chapel Royal Indigo

    return MaterialApp(
      title: 'KLC (OAU) Newcomers Extractor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
