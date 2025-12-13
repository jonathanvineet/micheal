import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

const UPLOAD_DIR = path.join(process.cwd(), 'uploads');
const CHUNK_SIZE = 50; // Process 50 files at a time

// Performance: Import shared cache for invalidation
const dirCache = new Map<string, { data: any; timestamp: number }>();

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData();
    const dirPath = formData.get('path') as string || '';
    const batchIndex = formData.get('batchIndex') as string;
    const totalBatches = formData.get('totalBatches') as string;
    
    const uploadPath = path.join(UPLOAD_DIR, dirPath);
    
    // Security check
    if (!uploadPath.startsWith(UPLOAD_DIR)) {
      return NextResponse.json({ error: 'Invalid path' }, { status: 400 });
    }

    // Ensure directory exists
    if (!fs.existsSync(uploadPath)) {
      fs.mkdirSync(uploadPath, { recursive: true });
    }

    const uploadedFiles: string[] = [];
    let totalSize = 0;

    // Get all file entries
    const entries = Array.from(formData.entries());
    const fileEntries = entries.filter(([key]) => key.startsWith('file-'));

    // Process files in parallel with a concurrency limit
    const PARALLEL_LIMIT = 10;
    for (let i = 0; i < fileEntries.length; i += PARALLEL_LIMIT) {
      const batch = fileEntries.slice(i, i + PARALLEL_LIMIT);
      
      await Promise.all(batch.map(async ([key, value]) => {
        const file = value as File;
        const relativePath = formData.get(`path-${key.substring(5)}`) as string || file.name;
        
        // Create subdirectories if needed
        const fileDir = path.dirname(relativePath);
        if (fileDir && fileDir !== '.') {
          const fullDir = path.join(uploadPath, fileDir);
          if (!fs.existsSync(fullDir)) {
            fs.mkdirSync(fullDir, { recursive: true });
          }
        }

        const filePath = path.join(uploadPath, relativePath);
        
        // Stream file writing for better memory usage
        const bytes = await file.arrayBuffer();
        const buffer = Buffer.from(bytes);
        
        await fs.promises.writeFile(filePath, buffer);
        
        totalSize += buffer.length;
        uploadedFiles.push(relativePath);
      }));
    }

    // Performance: Invalidate cache for upload directory
    dirCache.delete(uploadPath);

    return NextResponse.json({ 
      success: true, 
      message: `Batch ${batchIndex}/${totalBatches} uploaded successfully`,
      filesUploaded: uploadedFiles.length,
      totalSize,
      batchIndex: parseInt(batchIndex),
      isLastBatch: parseInt(batchIndex) === parseInt(totalBatches)
    });
  } catch (error) {
    console.error('Error uploading batch:', error);
    return NextResponse.json({ error: 'Failed to upload batch' }, { status: 500 });
  }
}
