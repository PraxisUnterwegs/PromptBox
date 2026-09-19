import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'app_controller.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final path = await StorageLocation.resolve();
  final controller = PromptBoxController(store: JsonPromptStore(path));
  await controller.initialize();
  runApp(PromptBoxApp(controller: controller));
}
