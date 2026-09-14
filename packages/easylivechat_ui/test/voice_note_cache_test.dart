import 'dart:io';

import 'package:easylivechat_ui/src/views/voice_note_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Downloading a voice note, which is the part that actually broke.
///
/// 0.1.69 wrote every download through ONE shared `<name>.part`. Two tiles can
/// prepare the same url at once — a message re-keys from its optimistic `tmp-`
/// id to the server's, which re-mounts the tile while the first download is
/// still running — so whichever finished first renamed the file out from under
/// the other, and the loser died with
/// `PathNotFoundException: Cannot rename file … No such file or directory`.
/// On the device that was every single voice note.
void main() {
  late HttpServer server;
  var requests = 0;
  final payload = List<int>.generate(4096, (i) => i % 256);

  setUp(() async {
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      final path = request.uri.path;
      if (path.endsWith('missing.m4a')) {
        request.response.statusCode = 404;
      } else if (path.endsWith('empty.m4a')) {
        request.response.statusCode = 200;
      } else {
        // Deliberately slow, so two callers really do overlap.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        request.response.add(payload);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    final dir = Directory('${Directory.systemTemp.path}/easylivechat-voice');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String url(String name) => 'http://${server.address.address}:${server.port}/$name';

  test('two tiles preparing the same note at once both get the file', () async {
    // The regression. Before the fix exactly one of these threw ENOENT.
    final results = await Future.wait([
      cacheVoiceNote(url('race.m4a')),
      cacheVoiceNote(url('race.m4a')),
    ]);

    expect(results[0], results[1], reason: 'both should land on one cached file');
    expect(requests, 1, reason: 'the note should cross the network once');
    final file = File(results[0]);
    expect(file.existsSync(), isTrue);
    expect(await file.readAsBytes(), payload);
    // No scratch file is left lying about.
    final dir = Directory('${Directory.systemTemp.path}/easylivechat-voice');
    expect(
      dir.listSync().where((e) => e.path.contains('.part')),
      isEmpty,
      reason: 'the losing attempt must clean up after itself',
    );
  });

  test('a second listen re-reads from disk instead of the network', () async {
    final first = await cacheVoiceNote(url('cached.m4a'));
    final before = requests;
    final second = await cacheVoiceNote(url('cached.m4a'));

    expect(second, first);
    expect(requests, before, reason: 'the cached file should be reused');
  });

  test('a 404 is reported as a fetch failure, not a rename one', () async {
    // It used to surface as a confusing ENOENT on the scratch file.
    await expectLater(
      cacheVoiceNote(url('missing.m4a')),
      throwsA(predicate((e) => e.toString().contains('404'))),
    );
  });

  test('an empty body is refused rather than cached as a playable file', () async {
    // A zero-byte file still "exists", so without this the cache would hand
    // the player an empty file for ever after.
    await expectLater(cacheVoiceNote(url('empty.m4a')), throwsA(isA<Object>()));
    final dir = Directory('${Directory.systemTemp.path}/easylivechat-voice');
    if (dir.existsSync()) {
      expect(dir.listSync().whereType<File>().where((f) => f.lengthSync() == 0), isEmpty);
    }
  });
}
