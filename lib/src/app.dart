import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'widgets/performance_overlay.dart';
import 'theme/kiln_theme.dart';

class BetterOqbApp extends StatelessWidget {
  const BetterOqbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Better OQB',
      builder: (context, child) => OqbPerformanceOverlay(child: child!),
      debugShowCheckedModeBanner: false,
      theme: buildKilnTheme(Brightness.light),
      darkTheme: buildKilnTheme(Brightness.dark),
      highContrastTheme: buildKilnTheme(Brightness.light).copyWith(
        dividerColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      highContrastDarkTheme: buildKilnTheme(Brightness.dark).copyWith(
        dividerColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
