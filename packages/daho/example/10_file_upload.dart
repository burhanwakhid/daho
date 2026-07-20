/// 10 — File Upload
///
/// Demonstrates multipart/form-data file upload handling:
/// - `req.body` — text fields from the form
/// - `req.files` — uploaded files keyed by field name
/// - `UploadedFile.save(path)` — write file to disk
/// - `UploadedFile.saveAsync(path)` — async variant
/// - `UploadedFile.filename`, `.contentType`, `.bytes`
///
/// Run:  dart run example/10_file_upload.dart
/// Test: Open http://localhost:8080 in a browser and use the upload form,
///       or use curl:
///   curl -X POST http://localhost:8080/upload \
///     -F "username=Alice" \
///     -F "avatar=@/path/to/photo.jpg"
library;

import 'dart:io';

import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  // Serve an HTML upload form
  app.get('/', (req, res) {
    return res.header('Content-Type', 'text/html').send('''
      <!DOCTYPE html>
      <html>
      <body style="font-family: sans-serif; padding: 40px;">
        <h2>Daho File Upload Demo</h2>
        <form action="/upload" method="POST" enctype="multipart/form-data">
          Username: <input type="text" name="username"><br><br>
          Avatar: <input type="file" name="avatar" required><br><br>
          <button type="submit">Upload</button>
        </form>
      </body>
      </html>
    ''');
  });

  // Handle the multipart/form-data upload
  app.post('/upload', (req, res) {
    // Read text fields from the form
    final username = req.body['username'] ?? 'Anonymous';

    // Read the uploaded file
    final avatar = req.files['avatar'];
    if (avatar == null) {
      return res.badRequest({'error': 'No file uploaded'});
    }

    // Ensure upload directory exists
    final uploadDir = Directory('./uploads');
    if (!uploadDir.existsSync()) {
      uploadDir.createSync();
    }

    // Save the file to disk
    final savePath = '${uploadDir.path}/${avatar.filename}';
    avatar.save(savePath);

    return res.status(201).json({
      'message': 'File uploaded successfully',
      'username': username,
      'filename': avatar.filename,
      'content_type': avatar.contentType,
      'size_bytes': avatar.bytes.length,
      'saved_to': savePath,
    });
  });
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
