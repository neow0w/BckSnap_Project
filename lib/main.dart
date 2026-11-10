import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AuthService().init(); // restores the saved login, if any
  await ThemeController.instance.load(); // restores light/dark
  runApp(const ScolioApp());
}

class ScolioApp extends StatelessWidget {
  const ScolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp.router(
        title: kIsWeb ? 'BckSnap Staff Portal' : 'Scoliosis Screening',
        theme: appTheme,
        darkTheme: appDarkTheme, // <- your dark theme
        themeMode: ThemeController.instance.mode,
        routerConfig: appRouter,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
