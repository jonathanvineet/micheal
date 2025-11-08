import { NextRequest, NextResponse } from 'next/server';
import Redis from 'ioredis';

// Redis client for persistent progress tracking (supports multi-instance deployments)
const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  // For local dev without Redis, use mock mode or fallback to in-memory
  lazyConnect: true,
  retryStrategy: () => null, // Don't retry if Redis unavailable
});

// Fallback to in-memory if Redis unavailable
let redisAvailable = false;
redis.connect().then(() => {
  redisAvailable = true;
  console.log('Redis connected for progress tracking');
}).catch(() => {
  console.warn('Redis unavailable, using in-memory progress tracking');
  redisAvailable = false;
});

const inMemoryProgress = new Map<string, { progress: number; total: number; status: string }>();

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const uploadId = searchParams.get('id');

  if (!uploadId) {
    return NextResponse.json({ error: 'Upload ID required' }, { status: 400 });
  }

  let progress;
  if (redisAvailable) {
    const data = await redis.get(`upload:${uploadId}`);
    progress = data ? JSON.parse(data) : null;
  } else {
    progress = inMemoryProgress.get(uploadId);
  }
  
  if (!progress) {
    return NextResponse.json({ progress: 0, total: 0, status: 'not_found' });
  }

  return NextResponse.json(progress);
}

export async function POST(request: NextRequest) {
  const { uploadId, progress, total, status } = await request.json();

  if (!uploadId) {
    return NextResponse.json({ error: 'Upload ID required' }, { status: 400 });
  }

  const progressData = { progress, total, status };

  if (redisAvailable) {
    await redis.set(`upload:${uploadId}`, JSON.stringify(progressData), 'EX', 300); // 5 min TTL
  } else {
    inMemoryProgress.set(uploadId, progressData);
    // Clean up after completion
    if (status === 'completed' || status === 'error') {
      setTimeout(() => {
        inMemoryProgress.delete(uploadId);
      }, 5000);
    }
  }

  return NextResponse.json({ success: true });
}

export async function updateProgress(uploadId: string, progress: number, total: number, status: string) {
  const progressData = { progress, total, status };
  if (redisAvailable) {
    await redis.set(`upload:${uploadId}`, JSON.stringify(progressData), 'EX', 300);
  } else {
    inMemoryProgress.set(uploadId, progressData);
  }
}

export async function clearProgress(uploadId: string) {
  if (redisAvailable) {
    await redis.del(`upload:${uploadId}`);
  } else {
    inMemoryProgress.delete(uploadId);
  }
}
