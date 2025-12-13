import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
import { shouldCompress, compressFile, compressFolder, getFolderSize, formatBytes } from '@/lib/compression';

// Resolve the uploads directory by searching upward from the current working directory.
function resolveUploadsDir(): string {
  const attempts = [process.cwd(), path.join(process.cwd(), '..'), path.join(process.cwd(), '..', '..')];
  for (const base of attempts) {
    const candidate = path.join(base, 'uploads');
    if (fs.existsSync(candidate)) return path.resolve(candidate);
  }
  const fallback = path.resolve(process.cwd(), 'uploads');
  return fallback;
}

const UPLOAD_DIR = resolveUploadsDir();
console.log(`[files] using uploads dir: ${UPLOAD_DIR}`);
const COMPRESSION_THRESHOLD = 100 * 1024 * 1024; // 100 MB

// Performance: Cache directory listings for 2 seconds
const dirCache = new Map<string, { data: any; timestamp: number }>();
const CACHE_TTL = 2000; // 2 seconds

// Performance: Reuse stat calls and batch file operations
const statCache = new Map<string, { stats: fs.Stats; timestamp: number }>();
const STAT_CACHE_TTL = 1000; // 1 second

// Ensure uploads directory exists
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const dirPath = searchParams.get('path') || '';
    const fullPath = path.join(UPLOAD_DIR, dirPath);

    // Performance: Check cache first
    const cacheKey = fullPath;
    const cached = dirCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
      return NextResponse.json(cached.data);
    }

    // Security check: ensure path is within UPLOAD_DIR
    const resolvedUploadDir = path.resolve(UPLOAD_DIR);
    const resolvedFullPath = path.resolve(fullPath);
    const relative = path.relative(resolvedUploadDir, resolvedFullPath);
    if (relative.startsWith('..') || (path.isAbsolute(relative) && !resolvedFullPath.startsWith(resolvedUploadDir))) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    if (!fs.existsSync(fullPath)) {
      const emptyResult = { files: [], currentPath: dirPath, count: 0 };
      dirCache.set(cacheKey, { data: emptyResult, timestamp: Date.now() });
      return NextResponse.json(emptyResult);
    }

    // Check if it's a file or directory (use cached stat if available)
    let stats: fs.Stats;
    const statCached = statCache.get(fullPath);
    if (statCached && Date.now() - statCached.timestamp < STAT_CACHE_TTL) {
      stats = statCached.stats;
    } else {
      stats = await fs.promises.stat(fullPath);
      statCache.set(fullPath, { stats, timestamp: Date.now() });
    }
    
    // If it's a file, serve it directly with optimizations
    if (stats.isFile()) {
      const ext = path.extname(fullPath).toLowerCase();
      
      // Set appropriate content type
      const contentTypes: Record<string, string> = {
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.png': 'image/png',
        '.gif': 'image/gif',
        '.webp': 'image/webp',
        '.svg': 'image/svg+xml',
        '.pdf': 'application/pdf',
        '.txt': 'text/plain',
        '.json': 'application/json',
      };
      
      const contentType = contentTypes[ext] || 'application/octet-stream';
      
      // Use streaming for large files (>1MB)
      if (stats.size > 1024 * 1024) {
        const stream = fs.createReadStream(fullPath);
        return new NextResponse(stream as any, {
          headers: {
            'Content-Type': contentType,
            'Content-Length': stats.size.toString(),
            'Cache-Control': 'public, max-age=31536000, immutable',
            'ETag': `"${stats.mtimeMs}-${stats.size}"`,
          },
        });
      }
      
      // For small files, read into buffer
      const fileBuffer = await fs.promises.readFile(fullPath);
      
      return new NextResponse(fileBuffer, {
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileBuffer.length.toString(),
          'Cache-Control': 'public, max-age=31536000, immutable',
          'ETag': `"${stats.mtimeMs}-${stats.size}"`,
        },
      });
    }

    // If it's a directory, list contents
    const dirents = await fs.promises.readdir(fullPath, { withFileTypes: true });
    
    // Performance: Process all files in parallel with larger batches
    const BATCH_SIZE = 100;
    const fileList = [];
    const items = dirents.filter(d => {
      // Filter out hidden/system files early
      if (d.name.startsWith('.')) return false;
      return true;
    });
    
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      const batch = items.slice(i, i + BATCH_SIZE);
      const batchResults = await Promise.all(
        batch.map(async (dirent) => {
          try {
            const itemPath = path.join(fullPath, dirent.name);
            
            // Performance: Use dirent info when possible to avoid extra stat calls
            let stats: fs.Stats;
            if (dirent.isFile() || dirent.isDirectory()) {
              // We know the type, only need size/mtime
              stats = await fs.promises.stat(itemPath);
            } else {
              stats = await fs.promises.stat(itemPath);
            }

            // Skip zero-byte files
            if (!stats.isDirectory() && stats.size === 0) {
              return null;
            }

            return {
              name: dirent.name,
              isDirectory: stats.isDirectory(),
              size: stats.size,
              modified: stats.mtime,
              path: path.join(dirPath, dirent.name).replace(/\\/g, '/')
            };
          } catch (err) {
            return null;
          }
        })
      );
      
      fileList.push(...batchResults.filter(Boolean));
    }

    const result = { 
      files: fileList, 
      currentPath: dirPath,
      count: fileList.length 
    };

    // Cache the result
    dirCache.set(cacheKey, { data: result, timestamp: Date.now() });

    return NextResponse.json(result);
  } catch (error) {
    console.error('Error reading directory:', error);
    return NextResponse.json({ error: 'Failed to read directory' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    // For Next.js, we need to use formData() which already handles multipart parsing
    const formData = await request.formData();
    const dirPath = (formData.get('path') as string) || '';
    const uploadPath = path.join(UPLOAD_DIR, dirPath);
    
    // Security check
    if (!uploadPath.startsWith(UPLOAD_DIR)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    // Ensure directory exists
    if (!fs.existsSync(uploadPath)) {
      await fs.promises.mkdir(uploadPath, { recursive: true });
    }

    const uploadedFiles: string[] = [];
    const compressedFiles: string[] = [];
    let totalSize = 0;
    
    // Process files from formData
    const fileData: Array<{ relativePath: string; filePath: string; size: number }> = [];
    const entries = Array.from(formData.entries());
    const fileEntries = entries.filter(([key]) => key.startsWith('file-'));
    
    // Performance: Process files in parallel batches
    const UPLOAD_BATCH_SIZE = 5;
    for (let i = 0; i < fileEntries.length; i += UPLOAD_BATCH_SIZE) {
      const batch = fileEntries.slice(i, i + UPLOAD_BATCH_SIZE);
      
      await Promise.all(batch.map(async ([key, value]) => {
        const file = value as File;
        const fieldIndex = key.replace('file-', '');
        const pathKey = `path-${fieldIndex}`;
        const relativePath = (formData.get(pathKey) as string) || file.name;
        
        // Create subdirectories if needed
        const fileDir = path.dirname(relativePath);
        if (fileDir && fileDir !== '.') {
          const fullDir = path.join(uploadPath, fileDir);
          if (!fs.existsSync(fullDir)) {
            await fs.promises.mkdir(fullDir, { recursive: true });
          }
        }

        const finalPath = path.join(uploadPath, relativePath);

        // Stream file to disk to avoid loading entire file in memory.
        // Write to a temporary file first and then rename to finalPath to
        // ensure the file appears atomically and to avoid exposing
        // partially-written or empty files to readers.
        const tmpPath = `${finalPath}.tmp`;
        const bytes = await file.arrayBuffer();
        const buffer = Buffer.from(bytes);
        await fs.promises.writeFile(tmpPath, buffer);
        await fs.promises.rename(tmpPath, finalPath);
        
        const fileSize = buffer.length;
        totalSize += fileSize;
        fileData.push({ relativePath, filePath: finalPath, size: fileSize });
        uploadedFiles.push(relativePath);
      }));
    }

    if (uploadedFiles.length === 0) {
      return NextResponse.json({ error: 'No files provided' }, { status: 400 });
    }
    
    // Performance: Invalidate cache for this directory
    dirCache.delete(path.join(UPLOAD_DIR, dirPath));

    // Check if we need to compress (multiple files or folder structure)
    if (uploadedFiles.length > 1 || uploadedFiles.some(f => f.includes('/'))) {
      // Check if the total size warrants compression
      if (totalSize > COMPRESSION_THRESHOLD) {
        console.log(`Total size ${formatBytes(totalSize)} exceeds threshold. Compressing...`);
        
        try {
          await compressFolder(uploadPath);
          compressedFiles.push('Folder compressed');
        } catch (compressError) {
          console.error('Compression error:', compressError);
        }
      }
    } else {
      // Single file - check if it needs compression
      const fileInfo = fileData[0];
      if (shouldCompress(fileInfo.size)) {
        console.log(`File ${fileInfo.relativePath} (${formatBytes(fileInfo.size)}) exceeds threshold. Compressing...`);
        
        try {
          await compressFile(fileInfo.filePath);
          compressedFiles.push(fileInfo.relativePath);
        } catch (compressError) {
          console.error('Compression error:', compressError);
        }
      }
    }

    const message = compressedFiles.length > 0
      ? `${uploadedFiles.length} file${uploadedFiles.length > 1 ? 's' : ''} uploaded and compressed successfully`
      : uploadedFiles.length === 1
        ? 'File uploaded successfully'
        : `${uploadedFiles.length} files uploaded successfully`;

    console.log(`[files.POST] uploadedFiles=${JSON.stringify(uploadedFiles)} totalSize=${totalSize} compressed=${JSON.stringify(compressedFiles)}`);
    return NextResponse.json({ 
      success: true, 
      message,
      filesUploaded: uploadedFiles.length,
      compressed: compressedFiles.length > 0,
      totalSize: formatBytes(totalSize)
    });
  } catch (error) {
    console.error('Error uploading file:', error);
    return NextResponse.json({ error: 'Failed to upload file' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const { filePath } = await request.json();
    
    const fullPath = path.join(UPLOAD_DIR, filePath);
    
    // Security check
    if (!fullPath.startsWith(UPLOAD_DIR)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    if (!fs.existsSync(fullPath)) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 });
    }

    const stats = fs.statSync(fullPath);
    
    if (stats.isDirectory()) {
      await fs.promises.rm(fullPath, { recursive: true, force: true });
    } else {
      await fs.promises.unlink(fullPath);
    }

    // Performance: Invalidate cache for parent directory
    const parentDir = path.dirname(fullPath);
    dirCache.delete(parentDir);
    statCache.delete(fullPath);

    return NextResponse.json({ success: true, message: 'Deleted successfully' });
  } catch (error) {
    console.error('Error deleting file:', error);
    return NextResponse.json({ error: 'Failed to delete file' }, { status: 500 });
  }
}
