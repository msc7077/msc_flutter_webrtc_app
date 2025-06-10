import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc_app/screens/name_input_screen.dart';
import 'package:get/get.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Flutter WebRTC Chat',
      debugShowCheckedModeBanner: false,
      home: NameInputScreen(),
    );
  }
}
