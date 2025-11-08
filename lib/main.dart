import 'package:acm_activity_comic_game_frontend/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'screens/code_entry_page.dart';
import 'route_observer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());

  final appState = AppState();
  await appState.load();
  runApp(ChangeNotifierProvider.value(value: appState, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legendary ProblemSet',
      theme: ThemeData(
        colorScheme: ColorScheme.light(primary: Colors.yellow[800]!),
      ),
      home: const CodeEntryPage(),
      navigatorObservers: [routeObserver],
    );
  }
}
