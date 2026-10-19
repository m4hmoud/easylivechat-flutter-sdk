/// A Dio that answers from a function instead of the network, and records
/// every request it was asked to make — so a test can assert on the exact body
/// and query the SDK puts on the wire, through the real [RestClient] code.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/rest_client.dart';

/// One canned answer.
class FakeReply {
  final int status;
  final Object? body;
  const FakeReply(this.status, [this.body]);
}

class FakeHttp implements HttpClientAdapter {
  FakeHttp(this.handler);

  /// Decides the reply for each request. Throw to simulate a transport error.
  FakeReply Function(RequestOptions request) handler;

  final List<RequestOptions> requests = [];

  /// Requests whose path ends with [suffix], in order.
  List<RequestOptions> to(String suffix) =>
      requests.where((r) => r.path.endsWith(suffix)).toList();

  /// The JSON body of a recorded request, as the SDK built it.
  static Map<String, dynamic> bodyOf(RequestOptions r) =>
      (r.data as Map).cast<String, dynamic>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = handler(options);
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A [RestClient] whose transport is [http]. `validateStatus` accepts
/// everything, as the SDK's own Dio does, so non-2xx bodies reach `throwFor`.
RestClient fakeRest(EasyLiveChatConfig config, FakeHttp http) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = http;
  return RestClient(config, dio: dio);
}
