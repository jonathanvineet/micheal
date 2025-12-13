import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

const UPLOAD_DIR = path.join(process.cwd(), 'uploads');

// Performance: Import shared cache from files route (for cache invalidation)
const dirCache = new Map<string, { data: any; timestamp: number }>();

export async function POST(request: NextRequest) {
  try {
    const { folderName, currentPath } = await request.json();

    if (!folderName) {
      return NextResponse.json({ error: 'Folder name is required' }, { status: 400 });
    }

    const fullPath = path.join(UPLOAD_DIR, currentPath || '', folderName);
    
    // Security check
    if (!fullPath.startsWith(UPLOAD_DIR)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    // Performance: Use async check
    const exists = await fs.promises.access(fullPath, fs.constants.F_OK).then(() => true).catch(() => false);
    if (exists) {
      return NextResponse.json({ error: 'Folder already exists' }, { status: 400 });
    }

    // Performance: Use async mkdir
    await fs.promises.mkdir(fullPath, { recursive: true });

    // Performance: Invalidate parent directory cache
    const parentDir = path.dirname(fullPath);
    dirCache.delete(parentDir);

    return NextResponse.json({ 
      success: true, 
      message: 'Folder created successfully',
      folderName 
    });
  } catch (error) {
    console.error('Error creating folder:', error);
    return NextResponse.json({ error: 'Failed to create folder' }, { status: 500 });
  }
}
