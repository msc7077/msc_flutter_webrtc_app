import 'dart:convert';
import 'dart:io';
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
  String roomId = 'room10';

  RxBool isSpeakerOn = false.obs;
  final isMicOn = true.obs;

  @override
  void onInit() async {
    super.onInit();
    if (Platform.isAndroid) {
      rtc.Helper.setSpeakerphoneOn(false); // 기본 수화기 모드
      isSpeakerOn.value = false; // 상태 변수도 맞춰주기
    } else {
      await rtc.Helper.ensureAudioSession();

      await rtc.Helper.setAppleAudioIOMode(
        rtc.AppleAudioIOMode.localAndRemote,
        preferSpeakerOutput: false,
      );
    }
  }

  Future<void> toggleSpeaker(enable) async {
    print('$TAG 🔁 toggleSpeaker: $enable');
    if (Platform.isAndroid) {
      rtc.Helper.setSpeakerphoneOn(enable); // 기본 수화기 모드
      isSpeakerOn.value = enable; // 상태 변수도 맞춰주기
    } else {
      // await rtc.Helper.ensureAudioSession();

      await rtc.Helper.setAppleAudioIOMode(
        rtc.AppleAudioIOMode.localAndRemote,
        preferSpeakerOutput: enable,
      );
      isSpeakerOn.value = enable; // 상태 변수도 맞춰주기
    }
  }

  /// ICE 서버 설정: TURN 서버 인증 정보 포함
  final Map<String, dynamic> iceServers = {
    'iceServers': [
      {
        'urls': [
          'turn:stageturn.kidkids.net:5349?transport=udp',
          'turn:stageturn.kidkids.net:5349?transport=tcp',
        ],
        'username': 'ekuser',
        'credential': 'kidkids!@#890',
      },
      // {'urls': 'stun:stun.l.google.com:19302'},
      // {
      //   'urls': 'turn:openrelay.metered.ca:80',
      //   'username': 'openrelayproject',
      //   'credential': 'openrelayproject',
      // },
    ],
  };

  /// 이름을 입력받고 소켓 연결을 초기화
  Future<void> init(String name) async {
    userName = name;
    await _initSocket();
  }

  /// 소켓 연결 및 이벤트 리스너 설정
  Future<void> _initSocket() async {
    socket = IO.io('wss://stagesignal.kidkids.net', {
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket!.connect();

    socket!
      ..on('connect', (_) => _onConnected())
      ..on('peers', _onPeers)
      ..on('new-peer', _onNewPeer)
      ..on('offer', _onOfferReceived)
      ..on('answer', _onAnswerReceived)
      ..on('ice-candidate', _onIceCandidateReceived)
      ..on('peer-disconnected', _onPeerDisconnected);
  }

  /// 소켓 연결 완료 시 호출
  void _onConnected() {
    selfId = socket!.id;
    print('$TAG 🔗 소켓 연결됨: $selfId');
    _joinRoom(roomId);
  }

  /// 기존 피어 목록 수신 처리 - 각 피어에 Offer 생성 요청
  void _onPeers(dynamic peerIds) async {
    final uniquePeers = Set<String>.from(peerIds);
    print('$TAG 🧑‍🧑‍🧒‍🧒 기존 피어 목록: $uniquePeers');
    for (var peerId in uniquePeers) {
      if (peerId != selfId) {
        _createOffer(peerId);
        await Future.delayed(Duration(milliseconds: 300));
      }
    }
  }

  /// 새 피어 참여 시 Offer 생성 요청
  void _onNewPeer(dynamic peerId) {
    print('$TAG 🔔 새 피어 참여: $peerId');
    // _createOffer(peerId);
  }

  /// Offer 수신 처리
  Future<void> _onOfferReceived(dynamic data) async {
    final from = data['from'];
    final offer = data['offer'];
    print('$TAG 📢 Offer 수신 from: $from');

    final pc = await _createPeerConnection(from);
    await pc.setRemoteDescription(
      rtc.RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    socket!.emit('answer', {
      'targetId': from,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  /// Answer 수신 처리
  Future<void> _onAnswerReceived(dynamic data) async {
    final from = data['from'];
    final answer = data['answer'];
    print('$TAG 📢 Answer 수신 from: $from');
    print('$TAG 📢 Answer 수신 peerConnections: ${peerConnections}');

    final pc = peerConnections[from];
    if (pc == null) {
      print('$TAG ⚠️ peerConnection 없음: $from');
      return;
    }

    // 내가 offer를 보냈을 경우에만 answer를 세팅해야 함
    if (from != selfId) {
      final signalingState = pc.signalingState;
      print('$TAG 🔍 signalingState: $signalingState');
      print(
        '$TAG 🔍 rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer: ${rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer}',
      );

      if (signalingState ==
          rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        try {
          await pc.setRemoteDescription(
            rtc.RTCSessionDescription(answer['sdp'], answer['type']),
          );
          print('$TAG ✅ Answer 설정 완료');
        } catch (e) {
          print('$TAG ❗ Answer 설정 오류: $e');
        }
      } else {
        print('$TAG ⚠️ signalingState가 have-local-offer 아님. Answer 설정 생략');
      }
    } else {
      print('$TAG ⚠️ Answer 보낸 사람과 selfId 같음. 내 answer 무시함.');
    }
  }

  /// ICE Candidate 수신 처리
  void _onIceCandidateReceived(dynamic data) {
    final from = data['from'];
    final candidate = data['candidate'];

    if (candidate != null) {
      final iceCandidate = rtc.RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );
      peerConnections[from]?.addCandidate(iceCandidate);
      print('$TAG 🧊 ICE Candidate 추가 from: $from');
    }
  }

  /// 피어 연결 종료 처리
  void _onPeerDisconnected(dynamic peerId) {
    print('$TAG ❌ 피어 연결 종료: $peerId');
    peerConnections[peerId]?.close();
    peerConnections.remove(peerId);
    dataChannels[peerId]?.close();
    dataChannels.remove(peerId);
  }

  /// 방 참여 및 로컬 미디어 스트림 획득
  Future<void> _joinRoom(String roomId) async {
    try {
      localStream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 1, // 단일 채널로 단순화
          'sampleRate': 16000, // 에코 제거에 유리한 낮은 샘플레이트
        },
        'video': false,
      });
      socket!.emit('join', roomId);
      print('$TAG 🎤 방 참여 완료 및 오디오 스트림 준비');
    } catch (e) {
      print('$TAG ❌ getUserMedia 실패: $e');
    }
  }

  /// 새로운 RTCPeerConnection 생성 및 이벤트 설정
  Future<rtc.RTCPeerConnection> _createPeerConnection(String peerId) async {
    // 기존 연결 있으면 닫고 새로 생성
    if (peerConnections.containsKey(peerId)) {
      await peerConnections[peerId]?.close();
      peerConnections.remove(peerId);
      dataChannels[peerId]?.close();
      dataChannels.remove(peerId);
    }

    final pc = await rtc.createPeerConnection(iceServers);
    peerConnections[peerId] = pc;

    // 로컬 트랙 추가 (오디오 등)
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        pc.addTrack(track, localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate != null) {
        socket!.emit('ice-candidate', {
          'targetId': peerId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'from': selfId,
        });
        print('$TAG 🌐 ICE Candidate 생성 및 전송: $peerId');
      }
    };

    pc.onIceConnectionState = (state) {
      print('$TAG 🌐 ICE 상태 변경 [$peerId]: $state');
      if (state == rtc.RTCIceConnectionState.RTCIceConnectionStateFailed) {
        print('$TAG ❌ ICE 연결 실패: $peerId');
      } else if (state ==
              rtc.RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == rtc.RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        print('$TAG ✅ ICE 연결 성공: $peerId');
      }
    };

    // 원격 트랙 수신 콜백 (오디오 수신 가능)
    pc.onTrack = (event) {
      print('$TAG 📡 원격 트랙 수신: $event');
    };

    // 원격 스트림 수신 (deprecated, 참고용)
    pc.onAddStream = (stream) {
      print('$TAG 📡 원격 스트림 수신: $stream');
    };

    // 데이터 채널 수신 처리 (상대가 만든 채널 받기)
    pc.onDataChannel = (channel) {
      print('$TAG 🔌 데이터 채널 수신: $channel');
      dataChannels[peerId] = channel;
      _setupDataChannel(peerId, channel);
    };

    return pc;
  }

  /// Offer 생성 및 전송 (상대방 피어에)
  Future<void> _createOffer(String peerId) async {
    print('$TAG ⚙️ Offer 생성 시작: $peerId');
    final pc = await _createPeerConnection(peerId);

    // 데이터 채널 생성 (내가 만든 채널)
    final dataChannel = await pc.createDataChannel(
      'chat',
      rtc.RTCDataChannelInit(),
    );
    dataChannels[peerId] = dataChannel;
    _setupDataChannel(peerId, dataChannel);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    socket!.emit('offer', {
      'targetId': peerId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });

    print('$TAG ⚙️ Offer 전송 완료: $peerId');
  }

  /// 데이터 채널 이벤트 설정 함수 분리
  void _setupDataChannel(String peerId, rtc.RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      print('$TAG 📶 데이터 채널 상태 변경 [$peerId]: $state');
      if (state == rtc.RTCDataChannelState.RTCDataChannelOpen) {
        print('$TAG ✅ 데이터 채널 열림: $peerId');
      }
    };

    channel.onMessage = (message) {
      _handleIncomingMessage(message.text);
    };
  }

  /// 메시지 전체 전송
  void sendMessageToAll(String msg) {
    final messageData = jsonEncode({
      'sender': userName ?? 'me',
      'name': userName ?? 'me',
      'message': msg,
    });

    dataChannels.forEach((peerId, channel) {
      if (channel.state == rtc.RTCDataChannelState.RTCDataChannelOpen) {
        channel.send(rtc.RTCDataChannelMessage(messageData));
        print('$TAG 📤 메시지 전송 [$peerId]: $messageData');
      }
    });

    _addMessage('$userName: $msg');
  }

  /// 메시지 수신 처리
  void _handleIncomingMessage(String raw) {
    try {
      final data = jsonDecode(raw);
      final sender = data['sender'];
      final name = data['name'] ?? sender;
      final msg = data['message'];
      if (sender != selfId) {
        _addMessage('$name: $msg');
      }
      print('$TAG 📥 메시지 수신 [$name]: $msg');
    } catch (e) {
      print('$TAG ❗ 메시지 파싱 오류: $e');
    }
  }

  /// 메시지 리스트에 추가 (GetX RxList 업데이트)
  void _addMessage(String msg) {
    messages.add(msg);
  }

  /// 마이크 토글 (켜기/끄기)
  void toggleMic() {
    final audioTrack = localStream?.getAudioTracks().first;
    if (audioTrack != null) {
      audioTrack.enabled = !audioTrack.enabled;
      isMicOn.value = audioTrack.enabled;
      print('$TAG 🎙️ 마이크 상태: ${audioTrack.enabled ? '켜짐' : '꺼짐'}');
    }
  }

  /// 방 나가기 처리
  Future<void> leaveRoom() async {
    print('$TAG 🚪 방 나가기');
    await socket?.disconnect();
    // 연결, 데이터 채널 모두 종료 및 초기화
    for (var pc in peerConnections.values) {
      await pc.close();
    }
    peerConnections.clear();

    for (var channel in dataChannels.values) {
      await channel.close();
    }
    dataChannels.clear();

    localStream?.dispose();
    localStream = null;
    messages.clear();
    userName = null;
    selfId = null;
  }
}
