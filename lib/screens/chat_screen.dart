import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/signaling_controller.dart';

class ChatScreen extends StatelessWidget {
  final SignalingController signalingController = Get.find();
  final TextEditingController _messageController = TextEditingController();

  ChatScreen() {
    signalingController.connectSocket(); // 화면 생성시 소켓 연결 시작
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text('채팅방 - ${signalingController.myName.value}')),
        actions: [
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () {
              Get.back(); // 나가기 (이름입력 화면으로 돌아감)
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              final msgs = signalingController.messages;
              return ListView.builder(
                itemCount: msgs.length,
                itemBuilder: (_, index) {
                  final msg = msgs[index];
                  final isMe = msg['name'] == signalingController.myName.value;

                  return ListTile(
                    title: Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueAccent : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['name']!,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isMe ? Colors.white : Colors.black,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              msg['message']!,
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
          Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(hintText: '메시지를 입력하세요'),
                    onSubmitted: (text) {
                      signalingController.sendMessage(text);
                      _messageController.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    signalingController.sendMessage(_messageController.text);
                    _messageController.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
