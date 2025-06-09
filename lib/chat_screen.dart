import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'signaling.dart';

class ChatScreen extends StatelessWidget {
  ChatScreen({super.key});
  final SignalingController signaling = Get.find(); // GetX로 컨트롤러 가져오기
  final TextEditingController msgController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${signaling.userName}의 채팅방')),
      body: Column(
        children: [
          // 📩 메시지 리스트
          Expanded(
            child: Obx(
              () => ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: signaling.messages.length,
                itemBuilder: (context, index) {
                  final msg = signaling.messages[index];
                  final isMine = msg.startsWith(signaling.userName! + ':');
                  return Align(
                    alignment:
                        isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isMine ? Colors.blue[100] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(msg),
                    ),
                  );
                },
              ),
            ),
          ),
          Obx(
            () => ElevatedButton(
              onPressed: () {
                if (signaling.isEarpiece.value) {
                  Helper.selectAudioOutput('speaker');
                  signaling.isEarpiece.value = false;
                } else {
                  Helper.selectAudioOutput('earpiece');
                  signaling.isEarpiece.value = true;
                }
              },
              child: Text(signaling.isEarpiece.value ? '스피커로 전환' : '수화기로 전환'),
            ),
          ),
          const SizedBox(height: 8),
          // ✏️ 입력창 + 보내기 버튼
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: msgController,
                    decoration: const InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final text = msgController.text.trim();
                    if (text.isNotEmpty) {
                      signaling.sendMessageToAll(text);
                      msgController.clear();
                    }
                  },
                  child: const Text('전송'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
