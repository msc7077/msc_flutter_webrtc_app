// lib/screens/name_input_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/signaling_controller.dart';
import 'chat_screen.dart';

class NameInputScreen extends StatelessWidget {
  final TextEditingController _nameController = TextEditingController();
  final SignalingController signalingController = Get.put(
    SignalingController(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('대화명 입력')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '대화명을 입력하세요',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              child: Text('입장하기'),
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isNotEmpty) {
                  signalingController.setMyName(name); // 이름 저장
                  Get.to(() => ChatScreen()); // 채팅방으로 이동
                } else {
                  Get.snackbar('오류', '대화명을 입력해주세요');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
