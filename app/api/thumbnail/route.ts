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
const MEMORY_CACHE_TTL = 60000; // 60 seconds (increased from 30s)
const MAX_MEMORY_CACHE_SIZE = 200; // Increased cache size

// Performance: Prevent duplicate simultaneous thumbnail generation (request deduplication)
const pendingRequests = new Map<string, Promise<{ buffer: Buffer; contentType: string; etag: string }>>();

// Performance: Limit concurrent thumbnail generation to prevent server overload
const MAX_CONCURRENT_THUMBNAILS = 3;
let activeThumbnailGenerations = 0;
const thumbnailQueue: Array<{ 
  key: string; 
  generator: () => Promise<{ buffer: Buffer; contentType: string; etag: string }>; 
  resolve: (value: { buffer: Buffer; contentType: string; etag: string }) => void; 
  reject: (reason: Error) => void 
}> = [];

// Process next item in queue
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
    // Process next in queue
    setImmediate(() => processQueue());
  }
}

// Generate thumbnail with queueing
async function generateThumbnailQueued(
  key: string,
  generator: () => Promise<{ buffer: Buffer; contentType: string; etag: string }>
): Promise<{ buffer: Buffer; contentType: string; etag: string }> {
  // Check if already pending
  const pending = pendingRequests.get(key);
  if (pending) {
    return pending;
  }
  
  // Create new promise
  const promise = new Promise<{ buffer: Buffer; contentType: string; etag: string }>((resolve, reject) => {
    thumbnailQueue.push({ key, generator, resolve, reject });
    processQueue();
  });
  
  pendingRequests.set(key, promise);
  return promise;
}

// Generate ETag from file stats
function generateETag(stats: fs.Stats): string {
  return `"${stats.mtime.getTime()}-${stats.size}"`;
}

// Generate video thumbnail using ffmpeg
async function generateVideoThumbnail(fullPath: string, thumbPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    const outTmp = thumbPath + '.jpg.tmp';
    const outFinal = thumbPath.replace(/\.[^.]+$/, '.jpg');

    // Improved ffmpeg command: try multiple seek positions if 1s fails
    const args = [
      '-ss', '1',           // Seek to 1 second
      '-i', fullPath,       // Input file
      '-frames:v', '1',     // Extract 1 frame
      '-q:v', '2',          // High quality
      '-vf', 'scale=\'min(320,iw)\':-2', // Scale preserving aspect ratio
      '-y',                 // Overwrite output
      outTmp
    ];
    
    const res = spawnSync('ffmpeg', args, { stdio: 'pipe', timeout: 5000 });
    
    if (res.status === 0 && fs.existsSync(outTmp)) {
      await fs.promises.rename(outTmp, outFinal);
      return await fs.promises.readFile(outFinal);
    }
    
    // If 1s seek failed, try at 0s (start of video)
    if (!fs.existsSync(outFinal)) {
      const args2 = [
        '-i', fullPath,
        '-frames:v', '1',
        '-q:v', '2',
        '-vf', 'scale=\'min(320,iw)\':-2',
        '-y',
        outTmp
      ];
      
      const res2 = spawnSync('ffmpeg', args2, { stdio: 'pipe', timeout: 5000 });
      
      if (res2.status === 0 && fs.existsSync(outTmp)) {
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

// Generate PDF thumbnail using pdftoppm or ghostscript
async function generatePdfThumbnail(fullPath: string, thumbPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    const outPrefix = thumbPath + '.pdfthumb';
    const outFinal = thumbPath.replace(/\.[^.]+$/, '.jpg');
    
    // Try pdftoppm first (part of poppler-utils)
    const args = [
      '-jpeg',
      '-f', '1',            // First page
      '-singlefile',
      '-scale-to', '1024',  // Scale to 1024px
      fullPath,
      outPrefix
    ];
    
    const res = spawnSync('pdftoppm', args, { stdio: 'pipe', timeout: 10000 });
    const produced = outPrefix + '.jpg';
    
    if (res.status === 0 && fs.existsSync(produced)) {
      await fs.promises.rename(produced, outFinal);
      return await fs.promises.readFile(outFinal);
    }
    
    // Fallback to ghostscript
    const gsArgs = [
      '-dNOPAUSE',
      '-dBATCH',
      '-dSAFER',
      '-sDEVICE=jpeg',
      '-dFirstPage=1',
      '-dLastPage=1',
      '-r150',              // 150 DPI
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

// Generate document thumbnail (DOCX, XLSX, etc.) using LibreOffice
async function generateDocumentThumbnail(fullPath: string, thumbPath: string): Promise<Buffer | null> {
  try {
    const { spawnSync } = await import('child_process');
    const tempDir = path.dirname(thumbPath);
    
    // Convert to PDF first using LibreOffice
    const args = [
      '--headless',
      '--convert-to', 'pdf',
      '--outdir', tempDir,
      fullPath
    ];
    
    spawnSync('libreoffice', args, { stdio: 'pipe', timeout: 15000 });
    
    // Check if PDF was created
    const expectedPdf = path.join(tempDir, path.basename(fullPath, path.extname(fullPath)) + '.pdf');
    
    if (fs.existsSync(expectedPdf)) {
      // Now convert PDF to JPEG
      const pdfBuffer = await generatePdfThumbnail(expectedPdf, thumbPath);
      
      // Cleanup temp PDF
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

    // Generate ETag for caching
    const etag = generateETag(stats);
    
    // Check If-None-Match header for 304 Not Modified
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

    // Determine thumbnail type and path
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
      // Regenerate if source file is newer
      if (thumbStats.mtime >= stats.mtime) {
        const buffer = await fs.promises.readFile(thumbPath);
        
        // Store in memory cache
        if (memoryCache.size >= MAX_MEMORY_CACHE_SIZE) {
          const firstKey = memoryCache.keys().next().value;
          if (firstKey) memoryCache.delete(firstKey);
        }
        memoryCache.set(memoryCacheKey, { buffer, contentType: 'image/jpeg', timestamp: Date.now(), etag });

        return new NextResponse(buffer, {
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
        if (sharp && (w > 0 || h > 0)) {
          try {
            buffer = await sharp(fullPath)
              .resize(w > 0 ? w : null, h > 0 ? h : null, { 
                fit: 'inside',
                withoutEnlargement: true,
                fastShrinkOnLoad: true
              })
              .jpeg({ quality: 80, progressive: true, mozjpeg: true })
              .toBuffer();
            
            // Save to disk cache
            if (buffer) {
              const tmp = thumbPath + '.tmp';
              await fs.promises.writeFile(tmp, buffer);
              await fs.promises.rename(tmp, thumbPath);
            }
          } catch (err) {
            console.error('Sharp thumbnail generation failed:', err);
            // Fallback to original for HEIC
            if (['.heic', '.heif'].includes(ext)) {
              buffer = await fs.promises.readFile(fullPath);
              contentType = ext === '.heif' ? 'image/heif' : 'image/heic';
            }
          }
        } else {
          // No resize requested or sharp unavailable
          buffer = await fs.promises.readFile(fullPath);
          contentType = ext === '.png' ? 'image/png' : ext === '.gif' ? 'image/gif' : 'image/jpeg';
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

      // Fallback to placeholder if generation failed
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
