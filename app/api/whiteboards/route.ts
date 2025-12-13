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

// Performance: Cache whiteboard listings
const whiteboardCache = { data: null as any, timestamp: 0 };
const WHITEBOARD_CACHE_TTL = 1000; // 1 second

export async function GET(request: NextRequest) {
  try {
    // Check cache first
    if (whiteboardCache.data && Date.now() - whiteboardCache.timestamp < WHITEBOARD_CACHE_TTL) {
      return NextResponse.json(whiteboardCache.data);
    }

    const whiteboardsDir = path.join(UPLOAD_DIR, 'whiteboards');

    if (!fs.existsSync(whiteboardsDir)) {
      const emptyResult = { files: [], currentPath: 'whiteboards', count: 0 };
      whiteboardCache.data = emptyResult;
      whiteboardCache.timestamp = Date.now();
      return NextResponse.json(emptyResult);
    }

    const dirents = await fs.promises.readdir(whiteboardsDir, { withFileTypes: true });
    
    // Performance: Process in parallel and filter efficiently
    const jsonFiles = dirents.filter(d => d.isFile() && d.name.endsWith('.json') && !d.name.endsWith('.deleted.json'));
    
    const files = await Promise.all(
      jsonFiles.map(async (dirent) => {
        try {
          const fullPath = path.join(whiteboardsDir, dirent.name);
          const stats = await fs.promises.stat(fullPath);
          
          if (stats.size === 0) return null;

          return {
            name: dirent.name,
            isDirectory: false,
            size: stats.size,
            modified: stats.mtime,
            path: `whiteboards/${dirent.name}`,
          };
        } catch (err) {
          return null;
        }
      })
    );

    const result = { 
      files: files.filter(Boolean), 
      currentPath: 'whiteboards', 
      count: files.filter(Boolean).length 
    };

    // Update cache
    whiteboardCache.data = result;
    whiteboardCache.timestamp = Date.now();

    return NextResponse.json(result);
  } catch (error) {
    console.error('whiteboards.GET error:', error);
    return NextResponse.json({ error: 'Failed to list whiteboards' }, { status: 500 });
  }
}
