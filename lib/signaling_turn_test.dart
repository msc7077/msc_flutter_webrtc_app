import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef OnSignalCallback = void Function(dynamic data);

class Signaling {
  final String serverUrl;
  final String roomId;
  final void Function(RTCSessionDescription sdp)? onOffer;
  final void Function(RTCSessionDescription sdp)? onAnswer;
  final void Function(RTCIceCandidate candidate)? onCandidate;

  late IO.Socket _socket;

  final String TAG = 'WebRTC Signaling';

  Signaling({
    required this.serverUrl,
    required this.roomId,
    this.onOffer,
    this.onAnswer,
    this.onCandidate,
  });

  void connect() {
    _socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket.onConnect((_) {
      print('$TAG 🔌 Connected to signaling server');
      _socket.emit('join', roomId);
    });

    _socket.on('offer', (data) {
      print('$TAG 📡 offer received');
      final sdp = RTCSessionDescription(data['sdp'], data['type']);
      onOffer?.call(sdp);
    });

    _socket.on('answer', (data) {
      print('$TAG 📡 answer received');
      final sdp = RTCSessionDescription(data['sdp'], data['type']);
      onAnswer?.call(sdp);
    });

    _socket.on('candidate', (data) {
      print('$TAG 📡 candidate received');
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      onCandidate?.call(candidate);
    });

    _socket.connect();
  }

  void send(String event, dynamic data) {
    _socket.emit(event, data);
  }

  void sendOffer(RTCSessionDescription offer) {
    send('offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  void sendAnswer(RTCSessionDescription answer) {
    send('answer', {'sdp': answer.sdp, 'type': answer.type});
  }

  void sendCandidate(RTCIceCandidate candidate) {
    send('candidate', {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }
}
