import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'core/router.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AuthService().init(); // restores the saved login, if any
  runApp(const ScolioApp());
}

class ScolioApp extends StatelessWidget {
  const ScolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: kIsWeb ? 'BckSnap Staff Portal' : 'Scoliosis Screening',
      theme: appTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
