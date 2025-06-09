import 'package:flutter/material.dart';
import 'package:flutter_webrtc_app/name_input_screen.dart';
import 'package:get/get.dart';
import 'chat_screen.dart';
import 'signaling.dart';

void main() {
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
