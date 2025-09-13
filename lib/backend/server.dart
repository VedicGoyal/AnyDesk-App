// lib/backend/server.dart
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';

class AnyDropServer {
  HttpServer? _server;
  late String sessionPath;
  late List<File> files;
  // at top of class
  int totalBytesSent = 0;
  void Function(int bytes)? onBytesSent; // you can hook this from UI
  /// Start the HTTP server that exposes:
  ///   GET /<session>/manifest       -> JSON list of {name,size}
  ///   GET /<session>/file?i=<idx>   -> streams the file at index
  Future<int> start(List<File> filesToSend, {int port = 0}) async {
    files = filesToSend;
    // random-ish session path, e.g. /mf9r13mc
    sessionPath = '/${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

    // Bind to all interfaces so peers on Wi-Fi/hotspot can connect.
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (e, st) {
      // You could surface this to UI if you want.
      // print('Server error: $e');
    });
    return _server!.port;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // Allow simple CORS (handy for opening link in a browser)
      req.response.headers.set('Access-Control-Allow-Origin', '*');

      // Only serve requests under this session path
      if (!req.uri.path.startsWith(sessionPath)) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }

      // GET /<session>/manifest
      if (req.method == 'GET' && req.uri.path.endsWith('/manifest')) {
        final manifest = <Map<String, Object>>[];
        for (final f in files) {
          final name =
              f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'file';
          int size = 0;
          try {
            size = f.lengthSync(); // may throw on some provider-backed files
          } catch (_) {
            size =
                0; // fall back; client can still download and show Unknown size
          }
          manifest.add({'name': name, 'size': size});
        }

        req.response.headers.contentType = ContentType.json;
        // Optional: set Content-Length to be super explicit for some clients
        final body = jsonEncode(manifest);
        req.response.headers.set(HttpHeaders.contentLengthHeader, body.length);
        req.response.write(body);
        await req.response.close();
        return;
      }

      // GET /<session>/file?i=<index>
      if (req.method == 'GET' && req.uri.path.endsWith('/file')) {
        final idx = int.tryParse(req.uri.queryParameters['i'] ?? '');
        if (idx == null || idx < 0 || idx >= files.length) {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
          return;
        }

        final file = files[idx];
        if (!await file.exists()) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }

        final fileName = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'file';
        final fileLen = await file.length();
        final contentType = lookupMimeType(fileName,
                headerBytes: await file.openRead(0, 16).first) ??
            'application/octet-stream';

        // Set headers before streaming
        req.response.headers
          ..set(HttpHeaders.contentTypeHeader, contentType)
          ..set(HttpHeaders.contentLengthHeader, fileLen)
          ..set(
            'Content-Disposition',
            'attachment; filename="$fileName"',
          );

        // Stream the file
        // instead of: await req.response.addStream(file.openRead());
        final stream = file.openRead().map((chunk) {
          totalBytesSent += chunk.length;
          if (onBytesSent != null) onBytesSent!(chunk.length);
          return chunk;
        });
        await req.response.addStream(stream);
        await req.response.close();
        return;
      }
      // GET /<session>/health
      if (req.method == 'GET' && req.uri.path.endsWith('/health')) {
        req.response.headers.contentType = ContentType.text;
        req.response.write('OK');
        await req.response.close();
        return;
      }

      // Unknown path under this session -> 404
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      // Best-effort error response without using headersSent (not available in dart:io)
      try {
        req.response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Ignore if headers already written
      }
      try {
        await req.response.close();
      } catch (_) {
        // Ignore if already closed
      }
    }
  }

  Future<void> stop() async {
    files = [];
    totalBytesSent = 0;

    await _server?.close(force: true);
    _server = null;
  }
}
