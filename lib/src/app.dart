import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/kiln_theme.dart';

class BetterOqbApp extends StatelessWidget {
  const BetterOqbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Better OQB',
      debugShowCheckedModeBanner: false,
      theme: buildKilnTheme(Brightness.light),
      darkTheme: buildKilnTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
