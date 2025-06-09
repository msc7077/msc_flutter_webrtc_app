import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'signaling.dart';
import 'chat_screen.dart';

class NameInputScreen extends StatelessWidget {
  NameInputScreen({super.key});
  final TextEditingController nameController = TextEditingController();
  final SignalingController signaling = Get.put(SignalingController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('채팅에서 사용할 이름을 입력하세요.', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  signaling.userName = name;
                  await signaling.init(name); // signaling 초기화
                  Get.to(() => ChatScreen()); // 채팅 화면으로 이동
                }
              },
              child: const Text('입장'),
            ),
          ],
        ),
      ),
    );
  }
}
