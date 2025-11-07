import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

const UPLOAD_DIR = path.join(process.cwd(), 'uploads');

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

    if (fs.existsSync(fullPath)) {
      return NextResponse.json({ error: 'Folder already exists' }, { status: 400 });
    }

    fs.mkdirSync(fullPath, { recursive: true });

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
