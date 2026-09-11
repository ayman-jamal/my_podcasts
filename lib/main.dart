import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/add_edit_screen.dart';
import 'screens/home_screen.dart';
import 'services/share_service.dart';
import 'state/podcast_store.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyPodcastsApp());
}

class MyPodcastsApp extends StatefulWidget {
  const MyPodcastsApp({super.key});

  @override
  State<MyPodcastsApp> createState() => _MyPodcastsAppState();
}

class _MyPodcastsAppState extends State<MyPodcastsApp> {
  final _store = PodcastStore();
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _store.init();
    // Shared while the app is already open.
    ShareService.listen(_handleShared);
    // App launched from the share sheet.
    _ready.then((_) async {
      final text = await ShareService.getInitialSharedText();
      if (text != null && text.trim().isNotEmpty) _handleShared(text);
    });
  }

  Future<void> _handleShared(String text) async {
    await _ready;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleShared(text));
      return;
    }
    await openAddFlow(navigator, text);
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _store,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'My Podcasts',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
