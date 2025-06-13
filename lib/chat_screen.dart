import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';
import 'signaling.dart';

class ChatMessage {
  final String text;
  final bool isSystem; // 새로운 참여자
  final bool isMine; // 나

  ChatMessage({required this.text, this.isSystem = false, this.isMine = false});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SignalingController signaling = Get.find(); // GetX로 컨트롤러 가져오기
  final TextEditingController msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // 메시지 리스트가 바뀔 때마다 자동 스크롤
    ever(signaling.messages, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // signaling.leaveRoom(); // 채팅방 나가기
          Get.back(); // 이전 화면으로 돌아가기
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${signaling.roomId}의 채팅방')),
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            // ElevatedButton(
            //   onPressed: () {
            //     signaling.leaveRoom();
            //     Get.back(); // 이전 화면으로 돌아가기
            //   },
            //   child: const Text('🚪 채팅방 나가기'),
            // ),
            const SizedBox(height: 8),
            // 📩 메시지 리스트
            Expanded(
              child: Obx(
                () => ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: signaling.messages.length,
                  itemBuilder: (context, index) {
                    final msg = signaling.messages[index];

                    if (msg.isSystem) {
                      // 시스템 메시지: 가운데 회색 박스
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            msg.text,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      );
                    }

                    final isMine = msg.text.startsWith(
                      signaling.userName! + ':',
                    );
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
                        child: Text(msg.text),
                      ),
                    );
                  },
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Obx(
                  () => ElevatedButton(
                    onPressed: () {
                      // if (Platform.isAndroid) {
                      //   if (signaling.isSpeakerOn.value) {
                      //     // 현재 스피커 ON 상태면 → 스피커 끄고, 상태도 false로
                      //     Helper.setSpeakerphoneOn(false);
                      //     signaling.isSpeakerOn.value = false;
                      //   } else {
                      //     // 현재 스피커 OFF 상태면 → 스피커 켜고, 상태도 true로
                      //     Helper.setSpeakerphoneOn(true);
                      //     signaling.isSpeakerOn.value = true;
                      //   }
                      // }
                      if (signaling.isSpeakerOn.value) {
                        signaling.toggleSpeaker(false);
                      } else {
                        signaling.toggleSpeaker(true);
                      }
                    },
                    child: Column(
                      children: [
                        Text(
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30),
                          signaling.isSpeakerOn.value
                              ? '📞' // true면 스피커 켜져있으니 스피커로 된 상태 표현
                              : '🎙️', // false면 수화기 상태
                        ),
                        Text(
                          textAlign: TextAlign.center,
                          signaling.isSpeakerOn.value
                              ? '수화기 모드' // true면 스피커 켜져있으니 스피커로 된 상태 표현
                              : '스피커 모드', // false면 수화기 상태
                        ),
                      ],
                    ),
                  ),
                ),
                Obx(
                  () => ElevatedButton(
                    child: Column(
                      children: [
                        Text(
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30),
                          signaling.isMicOn.value ? '🔇' : '🔊',
                        ),
                        Text(
                          textAlign: TextAlign.center,
                          signaling.isMicOn.value ? '마이크 OFF' : '마이크 ON',
                        ),
                      ],
                    ),
                    onPressed: () {
                      signaling.toggleMic();
                    },
                  ),
                ),
              ],
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
