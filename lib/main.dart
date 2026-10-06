import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/nav_state.dart';
import 'state/server_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = ServerStore()..load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(create: (_) => NavState()),
      ],
      child: const ControlApp(),
    ),
  );
}
