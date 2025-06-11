import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:get/get.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SignalingController extends GetxController {
  final String TAG = 'WebRtcApp';
  final String serverUrl = 'wss://stagesignal.kidkids.net';
  final String roomName = 'room10';

  var myName = ''.obs;
  IO.Socket? socket;
  String? selfId;

  var messages = <Map<String, dynamic>>[].obs; // 채팅 메시지 저장

  rtc.MediaStream? _localStream;
  rtc.MediaStream? get localStream => _localStream;

  // 피어 연결 및 원격 스트림 관리
  final Map<String, rtc.RTCPeerConnection> peerConnections = {};
  final Map<String, rtc.MediaStream> remoteStreams = {};

  // 데이터채널 관리를 위한 Map: peerId -> RTCDataChannel
  final Map<String, rtc.RTCDataChannel> dataChannels = {};

  void setMyName(String name) {
    myName.value = name;
  }

  void connectSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
    });

    socket!.onConnect((_) async {
      print('$TAG 🔗 1. 소켓 연결됨');
      selfId = socket!.id;
      socket!.emit('join', roomName);
      await _openUserMedia();
    });

    socket!.on('peers', (peerIds) {
      print('$TAG 🧑‍🧑‍🧒‍🧒 2. 기존 피어 수신: $peerIds');
      for (var peerId in peerIds) {
        if (peerId != selfId) {
          _createOffer(peerId);
        }
      }
    });

    socket!.on('new-peer', (peerId) {
      print('$TAG ➕ 새 피어 등장: $peerId');
      if (peerId != selfId) {
        _createOffer(peerId);
      }
    });

    socket!.on('offer', (data) async {
      final from = data['from'];
      final offer = data['offer'];
      print('$TAG 📥 Offer 수신 from: $from');

      await _createPeerConnection(from);
      await peerConnections[from]!.setRemoteDescription(
        rtc.RTCSessionDescription(offer['sdp'], offer['type']),
      );

      final answer = await peerConnections[from]!.createAnswer();
      await peerConnections[from]!.setLocalDescription(answer);

      socket!.emit('answer', {
        'to': from,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });

      print('$TAG 📤 Answer 전송 to: $from');
    });

    socket!.on('answer', (data) async {
      final from = data['from'];
      final sdp = data['sdp'];
      final pc = peerConnections[from];

      if (pc != null) {
        await pc.setRemoteDescription(rtc.RTCSessionDescription(sdp, 'answer'));
        print('$TAG ✅ Answer 수신 완료 from: $from');
      }
    });

    socket!.on('ice-candidate', (data) async {
      print('$TAG ✅ ice-candidate: $data');
      final from = data['from'];
      final candidateMap = data['candidate'];
      final candidate = rtc.RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );

      final pc = peerConnections[from];
      if (pc != null) {
        await pc.addCandidate(candidate);
        print('$TAG ❄️ ICE 후보 추가 from: $from');
      }
    });

    socket!.on('peer-disconnected', (peerId) {
      print('$TAG 🔌 피어 연결 종료: $peerId');
      peerConnections[peerId]?.close();
      peerConnections.remove(peerId);
      remoteStreams.remove(peerId);
      dataChannels.remove(peerId);
      update();
    });
  }

  // 사용자 미디어 열기
  Future<void> _openUserMedia() async {
    final stream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    _localStream = stream;
    update();
    print('$TAG 🎙️ 내 마이크 스트림 생성 완료');
  }

  // 피어 연결 생성 및 데이터채널 이벤트 핸들러 설정
  Future<void> _createPeerConnection(String peerId) async {
    if (peerConnections.containsKey(peerId)) return;

    final config = {
      'iceServers': [
        {
          'urls': [
            // 'turns:stageturn.kidkids.net:5349',
            'turn:stageturn.kidkids.net:5349?transport=udp',
            'turn:stageturn.kidkids.net:5349?transport=tcp',
          ],
          'username': 'ekuser',
          'credential': 'kidkids!@#890',
        },
      ],
    };

    final pc = await rtc.createPeerConnection(config);

    // 내 오디오 트랙 추가
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        pc.addTrack(track, _localStream!);
      }
    }

    // ICE 후보 이벤트 발생 시 서버에 전달
    pc.onIceCandidate = (candidate) {
      print('$TAG 🛜 pc.onIceCandidate: ${candidate.candidate}');
      if (candidate.candidate != null) {
        socket?.emit('ice-candidate', {
          'to': peerId,
          'from': selfId,
          'candidate': candidate.toMap(),
        });
        print('$TAG ❄️ ICE 전송 to: $peerId');
      }
    };

    // 원격 트랙 수신 이벤트 처리
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStreams[peerId] = event.streams[0];
        print('$TAG 🎧 상대방 오디오 스트림 수신 from: $peerId');
        update();
      }
    };

    // 데이터채널 이벤트 설정
    pc.onDataChannel = (rtc.RTCDataChannel channel) {
      print('$TAG 🔗 데이터채널 수신 from $peerId, label: ${channel.label}');
      _setupDataChannel(peerId, channel);
    };

    peerConnections[peerId] = pc;

    // 데이터채널을 먼저 만들고 이벤트 핸들러 등록 (Offer를 보내는 쪽에서만)
    if (selfId != null && selfId!.compareTo(peerId) < 0) {
      final dataChannelInit = rtc.RTCDataChannelInit();
      final dataChannel = await pc.createDataChannel('chat', dataChannelInit);
      _setupDataChannel(peerId, dataChannel);
      dataChannels[peerId] = dataChannel;
    }
  }

  // 데이터채널 이벤트 및 메시지 처리 함수
  void _setupDataChannel(String peerId, rtc.RTCDataChannel channel) {
    dataChannels[peerId] = channel;

    channel.onDataChannelState = (state) {
      print('$TAG 🔄 데이터채널 상태: $state from $peerId');
    };

    channel.onMessage = (rtc.RTCDataChannelMessage message) {
      print('$TAG 📩 데이터채널 메시지 수신 from $peerId: ${message.text}');
      try {
        final Map<String, dynamic> msgMap = jsonDecode(message.text);
        final senderName = msgMap['name'] ?? 'unknown';
        final text = msgMap['message'] ?? '';
        messages.add({'name': senderName, 'message': text});
        update();
      } catch (e) {
        print('$TAG ⚠️ 메시지 파싱 실패: $e');
      }
    };
  }

  // Offer 생성 및 전송
  Future<void> _createOffer(String peerId) async {
    await _createPeerConnection(peerId);
    final pc = peerConnections[peerId]!;

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    socket?.emit('offer', {
      'to': peerId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });

    print('$TAG 📤 Offer 전송 to: $peerId');
  }

  // 데이터채널을 이용한 채팅 메시지 전송
  void sendMessage(String text) {
    if (text.isEmpty) return;

    final msgMap = {'name': myName.value, 'message': text};

    final msgJson = jsonEncode(msgMap);
    messages.add(msgMap); // 로컬 채팅 기록 추가

    print('$TAG 🛜 dataChannels: $dataChannels');
    // 열린 데이터채널에 모두 메시지 전송
    dataChannels.forEach((peerId, channel) {
      if (channel.state == rtc.RTCDataChannelState.RTCDataChannelOpen) {
        channel.send(rtc.RTCDataChannelMessage(msgJson));
        print('$TAG 📤 데이터채널 메시지 전송 to: $peerId - $msgJson');
      }
    });

    update();
  }

  // 종료 및 리소스 정리
  void disconnect() {
    socket?.disconnect();
    peerConnections.forEach((_, pc) => pc.close());
    peerConnections.clear();
    remoteStreams.clear();

    dataChannels.forEach((_, channel) {
      channel.close();
    });
    dataChannels.clear();

    _localStream?.dispose();
    _localStream = null;
  }

  @override
  void onClose() {
    disconnect();
    super.onClose();
  }
}
