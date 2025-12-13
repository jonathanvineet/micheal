import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
// Dynamically import sharp if available; fall back to serving original image
let sharp: any = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  sharp = require('sharp');
} catch (e) {
  console.warn('sharp not available; thumbnails will be served without resizing');
}

function resolveUploadsDir(): string {
  const attempts = [process.cwd(), path.join(process.cwd(), '..'), path.join(process.cwd(), '..', '..')];
  for (const base of attempts) {
    const candidate = path.join(base, 'uploads');
    if (fs.existsSync(candidate)) return path.resolve(candidate);
  }
  return path.resolve(process.cwd(), 'uploads');
}

const UPLOAD_DIR = resolveUploadsDir();

// Performance: Cache generated thumbnails in memory for frequently accessed images
const memoryCache = new Map<string, { buffer: Buffer; contentType: string; timestamp: number }>();
const MEMORY_CACHE_TTL = 30000; // 30 seconds
const MAX_MEMORY_CACHE_SIZE = 50; // Max 50 thumbnails in memory

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const filePath = searchParams.get('path') || '';
    // Normalize any path segment that begins with the macOS resource-fork prefix `._`
    // by stripping the leading `._` so we resolve to the real file name. This
    // prevents errors when clients pass resource-fork style names.
    const normalizedSegments = filePath.split('/').map(seg => seg.startsWith('._') ? seg.slice(2) : seg);
    const normalizedFilePath = normalizedSegments.join('/');
    const fullPath = path.join(UPLOAD_DIR, normalizedFilePath);

    // Security check
    const resolvedUploadDir = path.resolve(UPLOAD_DIR);
    const resolvedFullPath = path.resolve(fullPath);
    const relative = path.relative(resolvedUploadDir, resolvedFullPath);
    if (relative.startsWith('..') || path.isAbsolute(relative) && !resolvedFullPath.startsWith(resolvedUploadDir)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    if (!fs.existsSync(fullPath)) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }

    const stats = fs.statSync(fullPath);
    if (stats.isDirectory()) {
      return NextResponse.json({ error: 'Not a file' }, { status: 400 });
    }

    const ext = path.extname(fullPath).toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif'];
    const videoExts = ['.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv'];
    const pdfExt = '.pdf';

    // If the filename is a hidden dotfile (starts with "."), skip thumbnail
    // generation and return a tiny transparent PNG placeholder. Resource-fork
    // names that start with `._` have already been normalized above.
    const baseName = path.basename(fullPath);
    if (baseName.startsWith('.')) {
      const onePixelPngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
      const buf = Buffer.from(onePixelPngBase64, 'base64');
      return new NextResponse(buf, {
        headers: { 'Content-Type': 'image/png', 'Content-Length': String(buf.length), 'Cache-Control': 'public, max-age=3600' }
      });
    }

    if (imageExts.includes(ext)) {
      // Support width/height query parameters for server-side resized thumbnails.
      const w = parseInt(searchParams.get('w') || '', 10) || 0;
      const h = parseInt(searchParams.get('h') || '', 10) || 0;

      // Thumbnail cache directory under uploads/.thumbs
      const thumbDir = path.join(UPLOAD_DIR, '.thumbs');
      if (!fs.existsSync(thumbDir)) fs.mkdirSync(thumbDir, { recursive: true });

      // Use encoded file path as a safe filename
      const safeName = encodeURIComponent(filePath).replace(/%2F/g, '__');
      const thumbName = w || h ? `${safeName}-${w}x${h}.jpg` : `${safeName}-orig${ext}`;
      const thumbPath = path.join(thumbDir, thumbName);

      // Performance: Check memory cache first for hot thumbnails
      const memoryCacheKey = thumbPath;
      const cachedThumb = memoryCache.get(memoryCacheKey);
      if (cachedThumb && Date.now() - cachedThumb.timestamp < MEMORY_CACHE_TTL) {
        return new NextResponse(cachedThumb.buffer, {
          headers: {
            'Content-Type': cachedThumb.contentType,
            'Content-Length': String(cachedThumb.buffer.length),
            'Cache-Control': 'public, max-age=86400',
            'ETag': `"${cachedThumb.timestamp}"`
          }
        });
      }

      // If thumbnail already exists on disk, serve it
      if (fs.existsSync(thumbPath)) {
        const buffer = await fs.promises.readFile(thumbPath);
        
        // Store in memory cache
        if (memoryCache.size >= MAX_MEMORY_CACHE_SIZE) {
          // Remove oldest entry
          const firstKey = memoryCache.keys().next().value;
          memoryCache.delete(firstKey);
        }
        memoryCache.set(memoryCacheKey, { buffer, contentType: 'image/jpeg', timestamp: Date.now() });

        return new NextResponse(buffer, {
          headers: {
            'Content-Type': 'image/jpeg',
            'Content-Length': String(buffer.length),
            'Cache-Control': 'public, max-age=86400'
          }
        });
      }

      // If sharp is available and a resize is requested, attempt to generate thumbnail.
      // If Sharp fails (unsupported format or missing codec), return a small placeholder
      // instead of attempting to stream an unsupported original file which can cause
      // client-side decode errors.
      if (sharp && (w > 0 || h > 0)) {
        try {
          // Performance: Use sharp with optimized settings
          const data = await sharp(fullPath)
            .resize(w > 0 ? w : null, h > 0 ? h : null, { 
              fit: 'inside',
              withoutEnlargement: true,
              fastShrinkOnLoad: true
            })
            .jpeg({ quality: 80, progressive: true, mozjpeg: true })
            .toBuffer();
          
          // Atomically write thumbnail
          const tmp = thumbPath + '.tmp';
          await fs.promises.writeFile(tmp, data);
          await fs.promises.rename(tmp, thumbPath);
          
          // Store in memory cache
          if (memoryCache.size >= MAX_MEMORY_CACHE_SIZE) {
            const firstKey = memoryCache.keys().next().value;
            memoryCache.delete(firstKey);
          }
          memoryCache.set(memoryCacheKey, { buffer: data, contentType: 'image/jpeg', timestamp: Date.now() });

          return new NextResponse(data, {
            headers: {
              'Content-Type': 'image/jpeg',
              'Content-Length': String(data.length),
              'Cache-Control': 'public, max-age=86400'
            }
          });
        } catch (err) {
          console.error('sharp thumbnail generation failed', err);
          // If Sharp failed due to unsupported format, behave conservatively:
          // - For HEIC/HEIF files, stream the original file with correct MIME so
          //   iOS clients can display it natively.
          // - For other unsupported formats, return a tiny PNG placeholder.
          const heicExts = ['.heic', '.heif'];
          if (heicExts.includes(ext)) {
            const mime = ext === '.heif' ? 'image/heif' : 'image/heic';
            const stream = fs.createReadStream(fullPath);
            return new NextResponse(stream as any, {
              headers: {
                'Content-Type': mime,
                'Cache-Control': 'public, max-age=3600'
              }
            });
          }

          const onePixelPngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
          const buf = Buffer.from(onePixelPngBase64, 'base64');
          return new NextResponse(buf, {
            headers: {
              'Content-Type': 'image/png',
              'Content-Length': String(buf.length),
              'Cache-Control': 'public, max-age=3600'
            }
          });
        }
      }

      // Serve original image if no resize requested (or sharp not available).
      // Map extension to content-type conservatively.
      const mime = ext === '.png' ? 'image/png' : ext === '.gif' ? 'image/gif' : ext === '.webp' ? 'image/webp' : 'image/jpeg';
      const stream = fs.createReadStream(fullPath);
      return new NextResponse(stream as any, {
        headers: {
          'Content-Type': mime,
          'Cache-Control': 'public, max-age=3600'
        }
      });
    }

    // Handle video thumbnails using ffmpeg if available (extract a frame).
    if (videoExts.includes(ext)) {
      try {
        const { spawnSync } = await import('child_process');
        // Prepare output thumb path (jpg)
        const outTmp = thumbPath + '.jpg.tmp';
        const outFinal = thumbPath.replace(/\.[^.]+$/, '.jpg');

        // ffmpeg command: seek to 1s, grab one frame, scale to fit width 320 preserving aspect
        const args = ['-ss', '1', '-i', fullPath, '-frames:v', '1', '-q:v', '2', '-vf', `scale=min(320\,iw):-2`, outTmp];
        const res = spawnSync('ffmpeg', args, { stdio: 'ignore' });
        if (res.status === 0 && fs.existsSync(outTmp)) {
          fs.renameSync(outTmp, outFinal);
          const data = fs.readFileSync(outFinal);
          return new NextResponse(data, { headers: { 'Content-Type': 'image/jpeg', 'Content-Length': String(data.length), 'Cache-Control': 'public, max-age=86400' } });
        }
      } catch (e) {
        // If ffmpeg missing or fails, fall through to placeholder
        console.warn('ffmpeg thumbnail generation failed', e);
      }
    }

    // Handle PDFs using pdftoppm (poppler) if available
    if (ext === pdfExt) {
      try {
        const { spawnSync } = await import('child_process');
        const outPrefix = thumbPath + '.pdfthumb';
        // pdftoppm -jpeg -f 1 -singlefile -scale-to 1024 input.pdf outPrefix
        const args = ['-jpeg', '-f', '1', '-singlefile', '-scale-to', '1024', fullPath, outPrefix];
        const res = spawnSync('pdftoppm', args, { stdio: 'ignore' });
        const produced = outPrefix + '.jpg';
        if (res.status === 0 && fs.existsSync(produced)) {
          // move to thumbPath
          fs.renameSync(produced, thumbPath.replace(/\.[^.]+$/, '.jpg'));
          const data = fs.readFileSync(thumbPath.replace(/\.[^.]+$/, '.jpg'));
          return new NextResponse(data, { headers: { 'Content-Type': 'image/jpeg', 'Content-Length': String(data.length), 'Cache-Control': 'public, max-age=86400' } });
        }
      } catch (e) {
        console.warn('pdftoppm failed', e);
      }
    }

    // For other non-image files return a tiny transparent PNG so client can display
    // a lightweight placeholder quickly (client will overlay an icon).
    const onePixelPngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
    const buf = Buffer.from(onePixelPngBase64, 'base64');
    return new NextResponse(buf, {
      headers: {
        'Content-Type': 'image/png',
        'Content-Length': String(buf.length),
        'Cache-Control': 'public, max-age=3600'
      }
    });
  } catch (err) {
    console.error('thumbnail GET error', err);
    return NextResponse.json({ error: 'Failed to generate thumbnail' }, { status: 500 });
  }
}
