import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// Flutter 앱의 시작점
void main() => runApp(MyApp());

// 메인 위젯 클래스 (StatefulWidget)
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

// 상태를 관리하는 클래스
class _MyAppState extends State<MyApp> {
  IO.Socket? socket; // Socket.IO 소켓 객체
  MediaStream? localStream; // 로컬 오디오/비디오 스트림
  Map<String, RTCPeerConnection> peerConnections = {}; // 피어 연결 목록
  Map<String, RTCDataChannel> dataChannels = {}; // 데이터 채널 목록
  List<String> messages = []; // 수신/송신된 메시지 저장 리스트
  String? selfId; // 현재 내 소켓 ID

  // ICE 서버 설정 (STUN/TURN 서버)
  final iceServers = {
    'iceServers': [
      {'urls': 'stun:stageturn.kidkids.net:3478'},
      {
        'urls': 'turn:stageturn.kidkids.net:3478',
        'username': 'ekuser',
        'credential': 'kidkids!@#890',
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    initSocket(); // 소켓 연결 초기화
  }

  // 소켓 연결 및 이벤트 등록
  void initSocket() {
    socket = IO.io('wss://stagesignal.kidkids.net', {
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    // 소켓 연결 완료 시
    socket!.on('connect', (_) {
      selfId = socket!.id;
      print('✅ 소켓 연결 완료: $selfId');
      joinRoom('room1');
    });

    // 방에 있는 기존 피어 목록 수신
    socket!.on('peers', (peerIds) {
      for (var peerId in peerIds) {
        createOffer(peerId); // 각 피어에 대해 Offer 생성
      }
    });

    // 새 피어가 참여함
    socket!.on('new-peer', (peerId) {
      print('🔔 새 피어 참여: $peerId');
    });

    // Offer 수신 시 처리
    socket!.on('offer', (data) async {
      String from = data['from'];
      Map<String, dynamic> offer = Map<String, dynamic>.from(data['offer']);
      await onOffer(from, offer);
    });

    // Answer 수신 시 처리
    socket!.on('answer', (data) async {
      String from = data['from'];
      Map<String, dynamic> answer = Map<String, dynamic>.from(data['answer']);
      await peerConnections[from]?.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });

    // ICE Candidate 수신 시 처리
    socket!.on('ice-candidate', (data) async {
      String from = data['from'];
      Map<String, dynamic>? candidate =
          data['candidate'] != null
              ? Map<String, dynamic>.from(data['candidate'])
              : null;
      if (candidate != null) {
        await peerConnections[from]?.addCandidate(
          RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ),
        );
      }
    });

    // 피어 연결 종료 시 처리
    socket!.on('peer-disconnected', (peerId) {
      print('❌ 피어 연결 종료: $peerId');
      peerConnections[peerId]?.close();
      peerConnections.remove(peerId);
      dataChannels[peerId]?.close();
      dataChannels.remove(peerId);
      setState(() {});
    });
  }

  // 방 참가 및 로컬 오디오 스트림 설정
  Future<void> joinRoom(String roomId) async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    socket!.emit('join', roomId);
  }

  // Offer 수신 시 처리 로직
  Future<void> onOffer(String from, dynamic offer) async {
    RTCPeerConnection pc = await createPeerConnection(iceServers);
    peerConnections[from] = pc;

    // 로컬 오디오 track 추가
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        pc.addTrack(track, localStream!);
      }
    }

    pc.onTrack = (event) {
      print('📡 원격 피어로부터 트랙 수신: $from');
    };

    pc.onDataChannel = (RTCDataChannel channel) {
      print('🔌 데이터 채널 수신: $from');
      dataChannels[from] = channel;

      channel.onMessage = (message) {
        _handleIncomingMessage(message.text);
      };
    };

    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );
    RTCSessionDescription answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    socket!.emit('answer', {
      'targetId': from,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  // Offer 생성 및 송신
  Future<void> createOffer(String peerId) async {
    RTCPeerConnection pc = await createPeerConnection(iceServers);
    peerConnections[peerId] = pc;

    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        pc.addTrack(track, localStream!);
      }
    }

    // 데이터 채널 생성
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit();
    RTCDataChannel dataChannel = await pc.createDataChannel(
      "chat",
      dataChannelDict,
    );
    dataChannels[peerId] = dataChannel;

    dataChannel.onMessage = (message) {
      _handleIncomingMessage(message.text);
    };

    RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    socket!.emit('offer', {
      'targetId': peerId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  // 모든 피어에게 메시지 전송
  void sendMessageAll(String msg) {
    final messageData = jsonEncode({'sender': selfId ?? 'me', 'message': msg});

    dataChannels.forEach((peerId, channel) {
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        channel.send(RTCDataChannelMessage(messageData));
        print('➡️ $peerId 에게 전송됨: $messageData');
      }
    });

    _addMessage('나: $msg');
  }

  // 수신 메시지 처리
  void _handleIncomingMessage(String raw) {
    try {
      final data = jsonDecode(raw);
      final msg = data['message'];
      final sender = data['sender'];
      if (sender != selfId) {
        _addMessage('$sender: $msg');
      }
    } catch (e) {
      print('❗ 메시지 파싱 오류: $e');
    }
  }

  // 메시지 리스트에 추가하고 화면 갱신
  void _addMessage(String msg) {
    setState(() {
      messages.add(msg);
    });
  }

  // UI 구성
  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController();

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Flutter WebRTC 채팅')), // 앱 타이틀
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(8),
                itemCount: messages.length,
                itemBuilder: (_, i) => Text(messages[i]),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    decoration: InputDecoration(hintText: '메시지를 입력하세요'),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    final msg = textController.text.trim();
                    if (msg.isNotEmpty) {
                      sendMessageAll(msg);
                      textController.clear();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
