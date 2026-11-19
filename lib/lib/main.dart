import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const LanMovieApp());
}

class LanMovieApp extends StatelessWidget {
  const LanMovieApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LAN Movie Player',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xffe53935),
      scaffoldBackgroundColor: const Color(0xff101117),
      cardTheme: CardThemeData(color: const Color(0xff1b1e28), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    home: const LibraryScreen(),
  );
}
