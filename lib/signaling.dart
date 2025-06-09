import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:get/get.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SignalingController extends GetxController {
  final String TAG = 'WebRtcApp';

  IO.Socket? socket;
  rtc.MediaStream? localStream;

  final Map<String, rtc.RTCPeerConnection> peerConnections = {};
  final Map<String, rtc.RTCDataChannel> dataChannels = {};
  final RxList<String> messages = <String>[].obs;
  String? selfId;
  String? userName;

  RxBool isEarpiece = false.obs; // 수화기 모드 여부 (예시로 추가)

  // ICE 서버 설정
  final Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stageturn.kidkids.net:3478'},
      {
        'urls': 'turn:stageturn.kidkids.net:3478',
        'username': 'ekuser',
        'credential': 'kidkids!@#890',
      },
    ],
  };

  // 초기화 (이름 입력 후 호출됨)
  Future<void> init(String name) async {
    userName = name;
    await _initSocket();
  }

  // 소켓 연결 및 이벤트 등록
  Future<void> _initSocket() async {
    socket = IO.io('wss://stagesignal.kidkids.net', {
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    // 소켓 연결 완료 시
    socket!.on('connect', (_) {
      selfId = socket!.id;
      print('$TAG ✅ 소켓 연결 완료: $selfId');
      _joinRoom('room1');
    });

    // 방에 있는 기존 피어 목록 수신
    socket!.on('peers', (peerIds) {
      print('$TAG 🧑‍🧑‍🧒‍🧒 방에 있는 기존 피어 목록 수신: $peerIds');
      for (var peerId in peerIds) {
        _createOffer(peerId);
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
      _onOffer(data['from'], data['offer']);
    });

    // Answer 수신 시 처리
    socket!.on('answer', (data) async {
      print('$TAG 📢 answer 수신: $data');
      final from = data['from'];
      final answer = data['answer'];
      await peerConnections[from]?.setRemoteDescription(
        rtc.RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });

    // ICE Candidate 수신 시 처리
    socket!.on('ice-candidate', (data) {
      print('$TAG 📢 ice-candidate 수신: $data');
      final from = data['from'];
      final candidate = data['candidate'];
      if (candidate != null) {
        peerConnections[from]?.addCandidate(
          rtc.RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ),
        );
      }
    });

    socket!.on('peer-disconnected', (peerId) {
      print('$TAG ❌ 피어 연결 종료: $peerId');
      peerConnections[peerId]?.close();
      peerConnections.remove(peerId);
      dataChannels[peerId]?.close();
      dataChannels.remove(peerId);
    });
  }

  // 방 참여 및 마이크 권한 획득
  Future<void> _joinRoom(String roomId) async {
    localStream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    socket!.emit('join', roomId);
  }

  // Offer 수신 처리
  Future<void> _onOffer(String from, dynamic offer) async {
    // from: 누가 Offer를 보냈는지 (상대방 피어 ID)
    // offer: 상대방이 보낸 WebRTC SDP Offer (sdp, type 포함)
    print('$TAG ⚙️ onOffer 수신 시 처리 로직 from: $from, offer: $offer');
    final pc = await rtc.createPeerConnection(iceServers);
    peerConnections[from] = pc;

    // 로컬 오디오 track 추가 : 로컬 오디오/비디오 트랙을 연결에 추가 (상대방이 수신 가능하게)
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        pc.addTrack(track, localStream!);
      }
    }

    // 상대방이 보내는 트랙(오디오/비디오)을 수신할 때 호출되는 콜백
    pc.onTrack = (event) {
      print('$TAG 📡 원격 피어로부터 트랙 수신: $from');
    };

    pc.onIceCandidate = (rtc.RTCIceCandidate candidate) {
      // ICE Candidate가 생성되면 상대방에게 전송
      print('$TAG 🌐 ICE Candidate 생성: $candidate');
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
    pc.onDataChannel = (rtc.RTCDataChannel channel) {
      print('🔌 데이터 채널 수신: $channel');
      dataChannels[from] = channel;

      channel.onMessage = (message) {
        _handleIncomingMessage(message.text);
      };
    };

    // 받은 offer를 원격 SDP로 설정
    // 서로 setLocalDescription / setRemoteDescription 및 ICE 교환이 완료되어야만 실제 연결이 됩니다. (이걸 시그널링 과정이라고 해요.)
    await pc.setRemoteDescription(
      rtc.RTCSessionDescription(offer['sdp'], offer['type']),
    );

    // Answer를 생성하고, 로컬 SDP로 설정
    // 📤 A → B 로 Offer 생성 및 전송
    rtc.RTCSessionDescription answer = await pc.createAnswer();
    // 서로 setLocalDescription / setRemoteDescription 및 ICE 교환이 완료되어야만 실제 연결이 됩니다. (이걸 시그널링 과정이라고 해요.)
    await pc.setLocalDescription(answer);

    // answer를 소켓을 통해 상대방에게 전송
    socket!.emit('answer', {
      'targetId': from,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  // Offer 생성 및 전송
  Future<void> _createOffer(String peerId) async {
    final pc = await rtc.createPeerConnection(iceServers);
    peerConnections[peerId] = pc;

    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        pc.addTrack(track, localStream!);
      }
    }

    // 데이터 채널 생성
    rtc.RTCDataChannelInit dataChannelDict = rtc.RTCDataChannelInit();
    rtc.RTCDataChannel dataChannel = await pc.createDataChannel(
      "chat",
      dataChannelDict,
    );
    dataChannels[peerId] = dataChannel;

    dataChannel.onMessage = (message) {
      _handleIncomingMessage(message.text);
    };

    rtc.RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    socket!.emit('offer', {
      'targetId': peerId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  // 모든 피어에게 메시지 전송
  void sendMessageToAll(String msg) {
    print('$TAG 📤 sendMessageAll: $msg');
    final messageData = jsonEncode({
      'sender': selfId ?? 'me',
      'name': userName ?? 'me',
      'message': msg,
    });

    print('$TAG 👀 dataChannels: $dataChannels');
    dataChannels.forEach((peerId, channel) {
      print('$TAG 👀 peerId: $peerId');
      if (channel.state == rtc.RTCDataChannelState.RTCDataChannelOpen) {
        channel.send(rtc.RTCDataChannelMessage(messageData));
        print('$TAG 📤 $peerId 에게 전송됨: $messageData');
      }
    });

    _addMessage('$userName: $msg');
  }

  // 수신 메시지 처리
  void _handleIncomingMessage(String raw) {
    print('$TAG 📥 _handleIncomingMessage: $raw');
    try {
      final data = jsonDecode(raw);
      final sender = data['sender']; // socket id
      final name = data['name'] ?? sender; // 닉네임 없으면 socket id
      final msg = data['message'];
      if (sender != selfId) {
        _addMessage('$name: $msg');
      }
    } catch (e) {
      print('$TAG ❗ 메시지 파싱 오류: $e');
    }
  }

  // 메시지 리스트에 추가
  void _addMessage(String msg) {
    messages.add(msg);
  }

  Future<void> leaveRoom() async {
    print('$TAG 👋 방 나가기 및 리소스 정리');
    print('$TAG 👋 localStream : ${localStream}');
    // 1. 로컬 스트림 종료
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        track.stop();
      }
      localStream = null;
    }

    print('$TAG 👋 peerConnections.values : ${peerConnections.values}');
    // 2. 모든 피어 연결 닫기
    for (var pc in peerConnections.values) {
      await pc.close();
    }
    peerConnections.clear();

    print('$TAG 👋 socket : ${socket}');
    // 4. 소켓 연결 종료 또는 방 나가기 이벤트 emit (필요 시)
    socket?.emit('peerClose', selfId);

    print('$TAG 👋 방 나가기 및 리소스 정리 완료');
  }
}
