import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

// Dynamically import sharp if available
let sharp: typeof import('sharp') | null = null;
try {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  sharp = require('sharp');
} catch {
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

// Performance: Cache generated thumbnails in memory
const memoryCache = new Map<string, { buffer: Buffer; contentType: string; timestamp: number; etag: string }>();
const MEMORY_CACHE_TTL = 60000; // 60 seconds
const MAX_MEMORY_CACHE_SIZE = 200; // Max 200 thumbnails in memory

// Performance: Prevent duplicate simultaneous thumbnail generation
const pendingRequests = new Map<string, Promise<{ buffer: Buffer; contentType: string; etag: string }>>();

// Performance: Limit concurrent thumbnail generation
const MAX_CONCURRENT_THUMBNAILS = 3;
let activeThumbnailGenerations = 0;
const thumbnailQueue: Array<{ 
  key: string; 
  generator: () => Promise<{ buffer: Buffer; contentType: string; etag: string }>; 
  resolve: (value: { buffer: Buffer; contentType: string; etag: string }) => void; 
  reject: (reason: Error) => void 
}> = [];

// Process queue with concurrency limit
async function processQueue() {
  if (activeThumbnailGenerations >= MAX_CONCURRENT_THUMBNAILS || thumbnailQueue.length === 0) {
    return;
  }
  
  const item = thumbnailQueue.shift();
  if (!item) return;
  
  activeThumbnailGenerations++;
  
  try {
    const result = await item.generator();
    item.resolve(result);
  } catch (error) {
    item.reject(error instanceof Error ? error : new Error(String(error)));
  } finally {
    activeThumbnailGenerations--;
    pendingRequests.delete(item.key);
    setImmediate(() => processQueue());
  }
}

// Queue thumbnail generation with deduplication
async function generateThumbnailQueued(
  key: string,
  generator: () => Promise<{ buffer: Buffer; contentType: string; etag: string }>
): Promise<{ buffer: Buffer; contentType: string; etag: string }> {
  const pending = pendingRequests.get(key);
  if (pending) {
    return pending;
  }
  
  const promise = new Promise<{ buffer: Buffer; contentType: string; etag: string }>((resolve, reject) => {
    thumbnailQueue.push({ key, generator, resolve, reject });
    processQueue();
  });
  
  pendingRequests.set(key, promise);
  return promise;
}

// Generate ETag
function generateETag(stats: fs.Stats): string {
  return `"${stats.mtime.getTime()}-${stats.size}"`;
}

// Convert HEIC to JPEG using ImageMagick or ffmpeg
async function convertHeicToJpeg(fullPath: string, outputPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    
    // Try ImageMagick convert first (fastest for HEIC)
    const args = [
      `${fullPath}[0]`,      // First image/frame
      '-resize', '320x320>',
      '-quality', '80',
      outputPath
    ];
    
    const res = spawnSync('convert', args, { stdio: 'pipe', timeout: 5000 });
    
    if (res.status === 0 && fs.existsSync(outputPath)) {
      return await fs.promises.readFile(outputPath);
    }
    
    // Fallback to ffmpeg if convert fails
    const ffmpegArgs = [
      '-i', fullPath,
      '-vframes', '1',
      '-vf', 'scale=\'min(320,iw)\':-2',
      '-q:v', '2',
      '-y',
      outputPath
    ];
    
    const ffmpegRes = spawnSync('ffmpeg', ffmpegArgs, { stdio: 'pipe', timeout: 5000 });
    
    if (ffmpegRes.status === 0 && fs.existsSync(outputPath)) {
      return await fs.promises.readFile(outputPath);
    }
    
    return null;
  } catch (error) {
    console.error('HEIC to JPEG conversion failed:', error);
    return null;
  }
}

// Generate video thumbnail - FIXED to extract actual frames
async function generateVideoThumbnail(fullPath: string, thumbPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    const outTmp = thumbPath + '.jpg.tmp';
    const outFinal = thumbPath.replace(/\.[^.]+$/, '.jpg');

    // Try multiple timestamps to find a good frame (avoid black frames at start)
    const timestamps = ['00:00:02', '00:00:01', '00:00:00.5'];
    
    for (const timestamp of timestamps) {
      const args = [
        '-ss', timestamp,           // Seek to timestamp BEFORE input (faster)
        '-i', fullPath,
        '-vframes', '1',             // Extract 1 frame
        '-vf', 'scale=320:320:force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2',
        '-q:v', '3',                 // Quality 3 (good quality)
        '-f', 'image2',              // Force image format
        '-update', '1',              // Update single image
        '-y',
        outTmp
      ];
      
      const res = spawnSync('ffmpeg', args, { 
        stdio: ['ignore', 'pipe', 'pipe'], 
        timeout: 8000,
        env: { ...process.env, AV_LOG_FORCE_NOCOLOR: '1' }
      });
      
      // Check if file was created and has content (not black frame)
      if (res.status === 0 && fs.existsSync(outTmp)) {
        const stats = fs.statSync(outTmp);
        if (stats.size > 1000) { // Valid frame should be > 1KB
          await fs.promises.rename(outTmp, outFinal);
          return await fs.promises.readFile(outFinal);
        }
        // Remove small/black frame and try next timestamp
        try { fs.unlinkSync(outTmp); } catch {}
      }
    }
    
    // Last resort: try to find any frame
    const args = [
      '-i', fullPath,
      '-vf', 'select=gt(scene\\,0.01),scale=320:320:force_original_aspect_ratio=decrease',
      '-frames:v', '1',
      '-vsync', 'vfr',
      '-q:v', '3',
      '-f', 'image2',
      '-y',
      outTmp
    ];
    
    const res = spawnSync('ffmpeg', args, { stdio: ['ignore', 'pipe', 'pipe'], timeout: 8000 });
    
    if (res.status === 0 && fs.existsSync(outTmp)) {
      const stats = fs.statSync(outTmp);
      if (stats.size > 500) {
        await fs.promises.rename(outTmp, outFinal);
        return await fs.promises.readFile(outFinal);
      }
    }
    
    return null;
  } catch (error) {
    console.error('Video thumbnail generation failed:', error);
    return null;
  }
}

// Generate PDF thumbnail
async function generatePdfThumbnail(fullPath: string, thumbPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    const outPrefix = thumbPath + '.pdfthumb';
    
    // Try pdftoppm first
    const args = [
      '-jpeg',
      '-f', '1',
      '-singlefile',
      '-scale-to', '1024',
      fullPath,
      outPrefix
    ];
    
    const res = spawnSync('pdftoppm', args, { stdio: 'pipe', timeout: 10000 });
    const produced = outPrefix + '.jpg';
    
    if (res.status === 0 && fs.existsSync(produced)) {
      const outFinal = thumbPath.replace(/\.[^.]+$/, '.jpg');
      await fs.promises.rename(produced, outFinal);
      return await fs.promises.readFile(outFinal);
    }
    
    // Fallback to ghostscript
    const outFinal = thumbPath.replace(/\.[^.]+$/, '.jpg');
    const gsArgs = [
      '-dNOPAUSE',
      '-dBATCH',
      '-dSAFER',
      '-sDEVICE=jpeg',
      '-dFirstPage=1',
      '-dLastPage=1',
      '-r150',
      '-dJPEGQ=85',
      `-sOutputFile=${outFinal}`,
      fullPath
    ];
    
    const gsRes = spawnSync('gs', gsArgs, { stdio: 'pipe', timeout: 10000 });
    
    if (gsRes.status === 0 && fs.existsSync(outFinal)) {
      return await fs.promises.readFile(outFinal);
    }
    
    return null;
  } catch (error) {
    console.error('PDF thumbnail generation failed:', error);
    return null;
  }
}

// Generate document thumbnail
async function generateDocumentThumbnail(fullPath: string, thumbPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    const tempDir = path.dirname(thumbPath);
    
    // Convert to PDF using LibreOffice
    const args = [
      '--headless',
      '--convert-to', 'pdf',
      '--outdir', tempDir,
      fullPath
    ];
    
    spawnSync('libreoffice', args, { stdio: 'pipe', timeout: 15000 });
    
    const expectedPdf = path.join(tempDir, path.basename(fullPath, path.extname(fullPath)) + '.pdf');
    
    if (fs.existsSync(expectedPdf)) {
      // Convert PDF to JPEG
      const pdfBuffer = await generatePdfThumbnail(expectedPdf, thumbPath);
      
      // Cleanup
      try {
        await fs.promises.unlink(expectedPdf);
      } catch {}
      
      return pdfBuffer;
    }
    
    return null;
  } catch (error) {
    console.error('Document thumbnail generation failed:', error);
    return null;
  }
}

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const filePath = searchParams.get('path') || '';
    
    // Normalize macOS resource-fork names
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

    const etag = generateETag(stats);
    const ifNoneMatch = request.headers.get('if-none-match');
    if (ifNoneMatch === etag) {
      return new NextResponse(null, { status: 304 });
    }

    const ext = path.extname(fullPath).toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp', '.tiff'];
    const videoExts = ['.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv', '.flv', '.wmv'];
    const pdfExt = '.pdf';
    const docExts = ['.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt', '.odt', '.ods', '.odp'];

    // Hidden files get placeholder
    const baseName = path.basename(fullPath);
    if (baseName.startsWith('.')) {
      const onePixelPngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
      const buf = Buffer.from(onePixelPngBase64, 'base64');
      return new NextResponse(buf, {
        headers: { 
          'Content-Type': 'image/png', 
          'Cache-Control': 'public, max-age=31536000, immutable',
          'ETag': etag
        }
      });
    }

    const w = parseInt(searchParams.get('w') || '', 10) || 0;
    const h = parseInt(searchParams.get('h') || '', 10) || 0;
    
    const thumbDir = path.join(UPLOAD_DIR, '.thumbs');
    if (!fs.existsSync(thumbDir)) await fs.promises.mkdir(thumbDir, { recursive: true });
    
    const safeName = encodeURIComponent(filePath).replace(/%2F/g, '__');
    const thumbName = w || h ? `${safeName}-${w}x${h}.jpg` : `${safeName}-thumb.jpg`;
    const thumbPath = path.join(thumbDir, thumbName);
    const memoryCacheKey = thumbPath;

    // Check memory cache first
    const cachedThumb = memoryCache.get(memoryCacheKey);
    if (cachedThumb && Date.now() - cachedThumb.timestamp < MEMORY_CACHE_TTL) {
      return new NextResponse(cachedThumb.buffer as unknown as BodyInit, {
        headers: {
          'Content-Type': cachedThumb.contentType,
          'Content-Length': String(cachedThumb.buffer.length),
          'Cache-Control': 'public, max-age=86400',
          'ETag': cachedThumb.etag
        }
      });
    }

    // Check disk cache
    if (fs.existsSync(thumbPath)) {
      const thumbStats = fs.statSync(thumbPath);
      if (thumbStats.mtime >= stats.mtime) {
        const buffer = await fs.promises.readFile(thumbPath);
        
        if (memoryCache.size >= MAX_MEMORY_CACHE_SIZE) {
          const firstKey = memoryCache.keys().next().value;
          if (firstKey) memoryCache.delete(firstKey);
        }
        memoryCache.set(memoryCacheKey, { buffer, contentType: 'image/jpeg', timestamp: Date.now(), etag });

        return new NextResponse(buffer as unknown as BodyInit, {
          headers: {
            'Content-Type': 'image/jpeg',
            'Cache-Control': 'public, max-age=86400',
            'ETag': etag
          }
        });
      }
    }

    // Generate thumbnail with queueing
    const result = await generateThumbnailQueued(memoryCacheKey, async () => {
      let buffer: Buffer | null = null;
      let contentType = 'image/jpeg';

      // IMAGE THUMBNAILS
      if (imageExts.includes(ext)) {
        // Special handling for HEIC/HEIF - use ImageMagick/ffmpeg instead of sharp
        if (['.heic', '.heif'].includes(ext)) {
          const outPath = thumbPath.replace(/\.[^.]+$/, '.jpg');
          buffer = await convertHeicToJpeg(fullPath, outPath);
          contentType = 'image/jpeg';
        } else if (sharp && (w > 0 || h > 0)) {
          try {
            buffer = await sharp(fullPath)
              .resize(w > 0 ? w : null, h > 0 ? h : null, { 
                fit: 'inside',
                withoutEnlargement: true,
                fastShrinkOnLoad: true
              })
              .jpeg({ quality: 80, progressive: true, mozjpeg: true })
              .toBuffer();
            
            if (buffer) {
              const tmp = thumbPath + '.tmp';
              await fs.promises.writeFile(tmp, buffer);
              await fs.promises.rename(tmp, thumbPath);
            }
          } catch (err) {
            console.error('Sharp thumbnail generation failed:', err);
            try {
              buffer = await fs.promises.readFile(fullPath);
              contentType = ext === '.png' ? 'image/png' : 'image/jpeg';
            } catch {
              // Fallback to placeholder
            }
          }
        } else {
          try {
            buffer = await fs.promises.readFile(fullPath);
            contentType = ext === '.png' ? 'image/png' : ext === '.gif' ? 'image/gif' : 'image/jpeg';
          } catch {
            // Fallback to placeholder
          }
        }
      }
      // VIDEO THUMBNAILS
      else if (videoExts.includes(ext)) {
        buffer = await generateVideoThumbnail(fullPath, thumbPath);
      }
      // PDF THUMBNAILS
      else if (ext === pdfExt) {
        buffer = await generatePdfThumbnail(fullPath, thumbPath);
      }
      // DOCUMENT THUMBNAILS
      else if (docExts.includes(ext)) {
        buffer = await generateDocumentThumbnail(fullPath, thumbPath);
      }

      // Fallback to placeholder
      if (!buffer) {
        const onePixelPngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
        buffer = Buffer.from(onePixelPngBase64, 'base64');
        contentType = 'image/png';
      }

      return { buffer, contentType, etag };
    });

    // Store in memory cache
    if (memoryCache.size >= MAX_MEMORY_CACHE_SIZE) {
      const firstKey = memoryCache.keys().next().value;
      if (firstKey) memoryCache.delete(firstKey);
    }
    memoryCache.set(memoryCacheKey, { ...result, timestamp: Date.now() });

    return new NextResponse(result.buffer as unknown as BodyInit, {
      headers: {
        'Content-Type': result.contentType,
        'Content-Length': String(result.buffer.length),
        'Cache-Control': 'public, max-age=86400',
        'ETag': result.etag
      }
    });
  } catch (err) {
    console.error('Thumbnail GET error:', err);
    return NextResponse.json({ error: 'Failed to generate thumbnail' }, { status: 500 });
  }
}
