import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

function resolveUploadsDir(): string {
  const attempts = [process.cwd(), path.join(process.cwd(), '..'), path.join(process.cwd(), '..', '..')];
  for (const base of attempts) {
    const candidate = path.join(base, 'uploads');
    if (fs.existsSync(candidate)) return path.resolve(candidate);
  }
  return path.resolve(process.cwd(), 'uploads');
}

const UPLOAD_DIR = resolveUploadsDir();

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const filePath = searchParams.get('path');

    if (!filePath) {
      return NextResponse.json({ error: 'File path is required' }, { status: 400 });
    }

    // Normalize incoming path segments to strip macOS resource-fork prefix `._`
    // so requests like `France/._FOO.jpg` map to `France/FOO.jpg`.
    const normalizedSegments = filePath.split('/').map(seg => seg.startsWith('._') ? seg.slice(2) : seg);
    const normalizedFilePath = normalizedSegments.join('/');
    if (normalizedFilePath !== filePath) {
      console.log('[download.GET] original path=', filePath, 'normalized=', normalizedFilePath);
    }

    // Resolve and ensure the path is inside the uploads directory
    const fullPath = path.resolve(UPLOAD_DIR, normalizedFilePath);

    // Security check: ensure resolved path is inside UPLOAD_DIR
    const relative = path.relative(UPLOAD_DIR, fullPath);
    if (relative.startsWith('..') || path.isAbsolute(relative) && !fullPath.startsWith(UPLOAD_DIR)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    if (!fs.existsSync(fullPath)) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    const stats = fs.statSync(fullPath);
    if (stats.isDirectory()) {
      return NextResponse.json({ error: 'Cannot download a directory' }, { status: 400 });
    }

    const fileName = path.basename(fullPath);
    const encodedFileName = encodeURIComponent(fileName);
    const ext = path.extname(fileName).toLowerCase();
    const contentTypes: Record<string, string> = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.pdf': 'application/pdf',
      '.mp4': 'video/mp4',
      '.mov': 'video/quicktime',
      '.mp3': 'audio/mpeg',
      '.wav': 'audio/wav',
      '.m4a': 'audio/mp4',
      '.json': 'application/json',
      '.txt': 'text/plain'
    };

    const contentType = contentTypes[ext] || 'application/octet-stream';

    // Support HTTP Range requests so clients (AVPlayer) can stream and seek
    // without downloading the entire file. If a Range header is provided,
    // respond with 206 Partial Content and the requested byte range.
    const rangeHeader = request.headers.get('range');
    const total = stats.size;
    const lastModified = stats.mtime.toUTCString();
    const etag = `"${stats.mtimeMs}-${stats.size}"`;
    
    const headers: Record<string, string> = {
      'Content-Disposition': `inline; filename*=UTF-8''${encodedFileName}`,
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'public, max-age=31536000, immutable',
      'Last-Modified': lastModified,
      'ETag': etag,
      'Connection': 'keep-alive'
    };

    // Performance: Support ETag caching
    const ifNoneMatch = request.headers.get('if-none-match');
    if (ifNoneMatch === etag) {
      return new NextResponse(null, { status: 304, headers });
    }

    if (rangeHeader) {
      // Example Range: "bytes=0-"
      const match = rangeHeader.match(/bytes=(\d+)-(\d+)?/);
      if (!match) {
        return NextResponse.json({ error: 'Invalid Range' }, { status: 416 });
      }
      const start = parseInt(match[1], 10);
      const end = match[2] ? parseInt(match[2], 10) : total - 1;
      if (start >= total || end >= total || start > end) {
        return NextResponse.json({ error: 'Requested Range Not Satisfiable' }, { status: 416 });
      }

      const chunkSize = (end - start) + 1;
      headers['Content-Range'] = `bytes ${start}-${end}/${total}`;
      headers['Content-Length'] = String(chunkSize);

      // Use larger buffer for video files (2MB) for faster streaming, standard 1MB for others
      const isVideo = ['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi'].includes(ext);
      const bufferSize = isVideo ? 1024 * 1024 * 2 : 1024 * 1024;
      const stream = fs.createReadStream(fullPath, { start, end, highWaterMark: bufferSize });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return new NextResponse(stream as any, { status: 206, headers });
    }

    // No Range header; serve the full file with optimized buffer
    headers['Content-Length'] = String(total);
    const isVideo = ['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi'].includes(ext);
    const bufferSize = isVideo ? 1024 * 1024 * 2 : 1024 * 1024;
    const stream = fs.createReadStream(fullPath, { highWaterMark: bufferSize });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return new NextResponse(stream as any, { headers });
  } catch (error) {
    console.error('Error downloading file:', error);
    return NextResponse.json({ error: 'Failed to download file' }, { status: 500 });
  }
}
