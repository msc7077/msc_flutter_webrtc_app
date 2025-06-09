import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/utils.dart';
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

  String TAG = 'WebRtcApp';

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
      print('$TAG ✅ 소켓 연결 완료: $selfId');
      joinRoom('room1');
    });

    // 방에 있는 기존 피어 목록 수신
    socket!.on('peers', (peerIds) {
      print('$TAG 🧑‍🧑‍🧒‍🧒 방에 있는 기존 피어 목록 수신: $peerIds');
      for (var peerId in peerIds) {
        createOffer(peerId);
      }
    });

    // 새 피어가 참여함
    socket!.on('new-peer', (peerId) {
      print('$TAG 🔔 새 피어 참여: $peerId');
    });

    // 서버로부터 offer 이벤트가 오면 실행되는 콜백
    // 새 피어가 참여했을 때 Offer를 생성하는 로직
    socket!.on('offer', (data) async {
      print('$TAG 📢 Offer 수신: $data');
      String from = data['from']; // from은 연결을 시도한 상대 피어의 ID
      Map<String, dynamic> offer = Map<String, dynamic>.from(data['offer']);
      // offer는 상대방이 보낸 WebRTC SDP Offer
      await onOffer(from, offer);
    });

    // Answer 수신 시 처리
    socket!.on('answer', (data) async {
      print('$TAG 📢 answer 수신: $data');
      String from = data['from'];
      Map<String, dynamic> answer = Map<String, dynamic>.from(data['answer']);
      // 서로 setLocalDescription / setRemoteDescription 및 ICE 교환이 완료되어야만 실제 연결이 됩니다. (이걸 시그널링 과정이라고 해요.)
      await peerConnections[from]?.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });

    // ICE Candidate 수신 시 처리
    socket!.on('ice-candidate', (data) async {
      print('$TAG 📢 ice-candidate 수신: $data');
      String from = data['from']; // Candidate를 보낸 새로 들어온 피어의 ID
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
      print('$TAG ❌ 피어 연결 종료: $peerId');
      peerConnections[peerId]?.close();
      peerConnections.remove(peerId);
      dataChannels[peerId]?.close();
      dataChannels.remove(peerId);
      setState(() {});
    });
  }

  // 방 참가 및 로컬 오디오 스트림 설정
  Future<void> joinRoom(String roomId) async {
    // 마이크 권한 요청
    // localStream 저장 → peer에 추가될 오디오
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    socket!.emit('join', roomId);
  }

  // Offer 수신 시 처리 로직
  Future<void> onOffer(String from, dynamic offer) async {
    // from: 누가 Offer를 보냈는지 (상대방 피어 ID)
    // offer: 상대방이 보낸 WebRTC SDP Offer (sdp, type 포함)
    print('$TAG ⚙️ onOffer 수신 시 처리 로직 from: $from, offer: $offer');
    // WebRTC 피어 연결 객체 생성 (iceServers는 STUN/TURN 서버 정보)
    RTCPeerConnection pc = await createPeerConnection(iceServers);
    print('$TAG ⚙️ pc > $pc');
    // 생성된 pc를 피어 ID를 키로 하여 저장
    peerConnections[from] = pc;
    print('$TAG ⚙️ peerConnections > $peerConnections');

    // 로컬 오디오 track 추가 : 로컬 오디오/비디오 트랙을 연결에 추가 (상대방이 수신 가능하게)
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        pc.addTrack(track, localStream!);
      }
    }

    // 상대방이 보내는 트랙(오디오/비디오)을 수신할 때 호출되는 콜백
    pc.onTrack = (event) {
      print('📡 원격 피어로부터 트랙 수신: $from');
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      // ICE Candidate가 생성되면 상대방에게 전송
      print('🌐 ICE Candidate 생성: $candidate');
      socket!.emit('ice-candidate', {
        'targetId': from,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        'from': selfId,
      });
    };

    // 상대방이 만든 RTCDataChannel을 수신했을 때
    // 받은 채널을 dataChannels에 저장
    // 채널에서 메시지가 오면 _handleIncomingMessage()로 처리
    pc.onDataChannel = (RTCDataChannel channel) {
      print('🔌 데이터 채널 수신: $channel');
      dataChannels[from] = channel;

      channel.onMessage = (message) {
        _handleIncomingMessage(message.text);
      };
    };

    // 받은 offer를 원격 SDP로 설정
    // 서로 setLocalDescription / setRemoteDescription 및 ICE 교환이 완료되어야만 실제 연결이 됩니다. (이걸 시그널링 과정이라고 해요.)
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    // Answer를 생성하고, 로컬 SDP로 설정
    // 📤 A → B 로 Offer 생성 및 전송
    RTCSessionDescription answer = await pc.createAnswer();
    // 서로 setLocalDescription / setRemoteDescription 및 ICE 교환이 완료되어야만 실제 연결이 됩니다. (이걸 시그널링 과정이라고 해요.)
    await pc.setLocalDescription(answer);

    // answer를 소켓을 통해 상대방에게 전송
    socket!.emit('answer', {
      'targetId': from,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  // Offer 생성 및 송신
  Future<void> createOffer(String peerId) async {
    print('$TAG ⚙️ createOffer Offer 생성 및 송신 peerId: $peerId');
    print(
      '$TAG ⚙️ createOffer Offer 생성 및 송신 peerConnections: $peerConnections',
    );
    // peerId는 방에 있는 다른 피어의 ID
    if (peerConnections.containsKey(peerId)) {
      print('$TAG ❗ 이미 연결된 피어: $peerId');
      return; // 이미 연결된 피어는 무시
    }
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
    print('$TAG 📤 sendMessageAll: $msg');
    final messageData = jsonEncode({'sender': selfId ?? 'me', 'message': msg});

    print('$TAG 👀 dataChannels: $dataChannels');
    dataChannels.forEach((peerId, channel) {
      print('$TAG 👀 peerId: $peerId');
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        channel.send(RTCDataChannelMessage(messageData));
        print('$TAG 📤 $peerId 에게 전송됨: $messageData');
      }
    });

    _addMessage('나: $msg');
  }

  // 수신 메시지 처리
  void _handleIncomingMessage(String raw) {
    print('$TAG 📥 _handleIncomingMessage: $raw');
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
    print('$TAG 📝 _addMessage: $msg');
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
            SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
