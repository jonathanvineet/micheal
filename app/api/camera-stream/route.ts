import { spawn, spawnSync, ChildProcess } from 'child_process';
import * as os from 'os';

// Shared FFmpeg process
let sharedFFmpegProcess: ChildProcess | null = null;
let lastFrame: Buffer | null = null;
let frameSubscribers = 0;
let restartTimeout: NodeJS.Timeout | null = null;
let detectedCameraIndex: string | null = null;
let detectedCameraName: string | null = null;

// Detect OS platform
const platform = os.platform(); // 'win32', 'darwin', 'linux'
const isWindows = platform === 'win32';
const isMac = platform === 'darwin';
const isLinux = platform === 'linux';

// Track active connections with timestamps
const activeConnections = new Map<number, number>();
let connectionIdCounter = 0;

// Cleanup stale connections every 2 seconds
setInterval(() => {
  const now = Date.now();
  const staleThreshold = 30000; // 30 seconds
  
  for (const [id, lastActivity] of activeConnections.entries()) {
    if (now - lastActivity > staleThreshold) {
      console.log(`🧹 Cleaning up stale connection ${id}`);
      activeConnections.delete(id);
      frameSubscribers = Math.max(0, frameSubscribers - 1);
    }
  }
}, 2000);

// Detect webcam device
function detectWebcam(): string | null {
  if (detectedCameraIndex !== null) {
    return detectedCameraIndex;
  }

  try {
    console.log(`🔍 Detecting webcam on ${platform}...`);
    
    let output = '';
    
    let result;
    if (isWindows) {
      // Windows: Use DirectShow to list devices
      result = spawnSync('ffmpeg', ['-list_devices', 'true', '-f', 'dshow', '-i', 'dummy'], {
        encoding: 'utf-8'
      });
    } else if (isMac) {
      // macOS: Use AVFoundation
      result = spawnSync('ffmpeg', ['-f', 'avfoundation', '-list_devices', 'true', '-i', ''], {
        encoding: 'utf-8'
      });
    } else {
      // Linux: Use v4l2
      result = spawnSync('ffmpeg', ['-f', 'v4l2', '-list_devices', 'true', '-i', 'dummy'], {
        encoding: 'utf-8'
      });
    }
    
    // FFmpeg outputs device list to stderr
    output = result.stderr || result.stdout || '';
    
    if (result.error) {
      console.log('⚠️ Error running ffmpeg:', result.error.message);
    }
    
    console.log('Camera detection output length:', output.length);
    if (output.length > 0) {
      console.log('First 500 chars:', output.substring(0, 500));
    }
    
    // Parse won't work because output is on stderr, so we catch it
    if (!output) {
      console.warn('⚠️ No output from ffmpeg detection command');
      return null;
    }
    
    if (isWindows) {
      // Windows DirectShow parsing - look for C110 or Logitech webcam
      const lines = output.split('\n');
      console.log(`📋 Parsing ${lines.length} lines of output...`);
      
      for (const line of lines) {
        // Look for video devices containing C110 or Logitech
        if (line.includes('"') && line.includes('(video)')) {
          console.log(`🎥 Found video line: ${line.trim()}`);
          const match = line.match(/"([^"]+)"/);
          if (match) {
            detectedCameraName = match[1];
            detectedCameraIndex = `video=${detectedCameraName}`;
            console.log(`✅ Detected camera: ${detectedCameraName}`);
            
            // Prefer C110 or Logitech webcams
            if (detectedCameraName.toLowerCase().includes('c110') || 
                detectedCameraName.toLowerCase().includes('logitech') ||
                detectedCameraName.toLowerCase().includes('webcam')) {
              console.log(`🎯 Using preferred camera: ${detectedCameraName}`);
              return detectedCameraIndex;
            }
          }
        }
      }
      
      // If we found any video device, use it
      if (detectedCameraIndex) {
        console.log(`✅ Using video device: ${detectedCameraName}`);
        return detectedCameraIndex;
      }
      
      console.warn('⚠️ Could not detect webcam on Windows');
      return null;
      
    } else if (isMac) {
      // macOS AVFoundation parsing
      const lines = output.split('\n');
      for (const line of lines) {
        // Prioritize Logitech webcam
        const logiMatch = line.match(/\[(\d+)\].*(?:Logitech|C110|C920|C922|Webcam)/i);
        if (logiMatch) {
          detectedCameraIndex = logiMatch[1];
          console.log(`✅ Found Logitech webcam at index: ${detectedCameraIndex}`);
          console.log(`   Device: ${line.trim()}`);
          return detectedCameraIndex;
        }
      }
      
      // If no Logitech found, look for any external camera (not FaceTime)
      for (const line of lines) {
        if (line.includes('[') && line.includes(']') && !line.toLowerCase().includes('facetime')) {
          const match = line.match(/\[(\d+)\]/);
          if (match) {
            detectedCameraIndex = match[1];
            console.log(`✅ Found external camera at index: ${detectedCameraIndex}`);
            console.log(`   Device: ${line.trim()}`);
            return detectedCameraIndex;
          }
        }
      }
      
      // Last resort: try index 1 (usually USB on Mac)
      console.warn('⚠️ Could not auto-detect USB webcam, defaulting to index 1');
      detectedCameraIndex = '1';
      return detectedCameraIndex;
      
    } else {
      // Linux v4l2 parsing
      const lines = output.split('\n');
      for (const line of lines) {
        if (line.includes('/dev/video')) {
          const match = line.match(/\/dev\/video(\d+)/);
          if (match) {
            detectedCameraIndex = `/dev/video${match[1]}`;
            console.log(`✅ Found video device: ${detectedCameraIndex}`);
            return detectedCameraIndex;
          }
        }
      }
      
      // Fallback to /dev/video0
      console.warn('⚠️ Could not auto-detect webcam, defaulting to /dev/video0');
      detectedCameraIndex = '/dev/video0';
      return detectedCameraIndex;
    }
  } catch (outerError: unknown) {
    console.error('❌ Error in detectWebcam:', outerError);
    return null;
  }
  
  return null;
}

// Start shared FFmpeg process
function startSharedFFmpeg() {
  if (sharedFFmpegProcess) return;
  
  const cameraIndex = detectWebcam();
  if (cameraIndex === null) {
    console.error('❌ No webcam detected!');
    return;
  }
  
  console.log(`🎥 Starting shared FFmpeg process with camera: ${cameraIndex}...`);
  
  let ffmpegArgs: string[];
  
  if (isWindows) {
    // Windows DirectShow
    ffmpegArgs = [
      '-f', 'dshow',
      '-framerate', '30',
      '-video_size', '1024x768',
      '-i', cameraIndex, // format: "video=Camera Name"
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      '-q:v', '3',
      '-',
    ];
  } else if (isMac) {
    // macOS AVFoundation
    ffmpegArgs = [
      '-f', 'avfoundation',
      '-framerate', '30',
      '-video_size', '1024x768',
      '-i', cameraIndex, // format: "0" or "1"
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      '-q:v', '3',
      '-',
    ];
  } else {
    // Linux v4l2
    ffmpegArgs = [
      '-f', 'v4l2',
      '-framerate', '30',
      '-video_size', '1024x768',
      '-i', cameraIndex, // format: "/dev/video0"
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      '-q:v', '3',
      '-',
    ];
  }
  
  // Use 1024x768 for Logitech C110 webcam (widely supported by USB webcams)
  sharedFFmpegProcess = spawn('ffmpeg', ffmpegArgs);

  let buffer = Buffer.alloc(0);
  const jpegStart = Buffer.from([0xFF, 0xD8]);
  const jpegEnd = Buffer.from([0xFF, 0xD9]);

  sharedFFmpegProcess.stdout?.on('data', (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk]);

    // Extract complete JPEG frames
    while (true) {
      const startIdx = buffer.indexOf(jpegStart);
      if (startIdx === -1) {
        if (buffer.length > 500000) buffer = Buffer.alloc(0);
        break;
      }

      const endIdx = buffer.indexOf(jpegEnd, startIdx + 2);
      if (endIdx === -1) {
        if (buffer.length > 500000) buffer = Buffer.alloc(0);
        break;
      }

      // Extract and store latest frame
      lastFrame = buffer.slice(startIdx, endIdx + 2);
      buffer = buffer.slice(endIdx + 2);
    }
  });

  sharedFFmpegProcess.stderr?.on('data', (data: Buffer) => {
    const msg = data.toString();
    if (!msg.includes('frame=') && !msg.includes('fps=')) {
      console.log('FFmpeg:', msg.trim());
    }
  });

  sharedFFmpegProcess.on('exit', (code) => {
    console.log(`FFmpeg exited with code ${code}`);
    sharedFFmpegProcess = null;
    lastFrame = null;
    
    // Restart if still have subscribers
    if (frameSubscribers > 0) {
      console.log('♻️ Restarting FFmpeg for active subscribers...');
      setTimeout(startSharedFFmpeg, 1000);
    }
  });
}

// Stop FFmpeg when no subscribers
function scheduleFFmpegStop() {
  if (restartTimeout) clearTimeout(restartTimeout);
  
  restartTimeout = setTimeout(() => {
    if (frameSubscribers === 0 && sharedFFmpegProcess) {
      console.log('🛑 No subscribers, stopping FFmpeg...');
      sharedFFmpegProcess.kill('SIGTERM');
      sharedFFmpegProcess = null;
      lastFrame = null;
    }
  }, 5000);
}

export async function GET() {
  const boundary = 'FRAME';
  const encoder = new TextEncoder();
  
  // Limit maximum concurrent subscribers
  if (frameSubscribers >= 10) {
    console.warn(`⚠️  Too many subscribers (${frameSubscribers}), rejecting new connection`);
    return new Response('Too many connections', { status: 503 });
  }
  
  // Assign unique ID to this connection
  const connectionId = ++connectionIdCounter;
  activeConnections.set(connectionId, Date.now());
  
  frameSubscribers++;
  console.log(`📱 Client ${connectionId} connected. Active subscribers: ${frameSubscribers}`);
  
  // Clear any pending stop
  if (restartTimeout) {
    clearTimeout(restartTimeout);
    restartTimeout = null;
  }
  
  // Start FFmpeg if not running
  if (!sharedFFmpegProcess) {
    startSharedFFmpeg();
  }

  const stream = new ReadableStream({
    async start(controller) {
      let active = true;
      let lastSentFrame: Buffer | null = null;
      
      // Send initial frame immediately if available
      if (lastFrame) {
        try {
          const header = `--${boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: ${lastFrame.length}\r\n\r\n`;
          controller.enqueue(encoder.encode(header));
          controller.enqueue(new Uint8Array(lastFrame));
          controller.enqueue(encoder.encode('\r\n'));
          lastSentFrame = lastFrame;
          activeConnections.set(connectionId, Date.now()); // Update activity
        } catch (err) {
          console.error('Error sending initial frame:', err);
        }
      }
      
      // Polling loop - read latest frame and send if different
      const sendFrames = setInterval(() => {
        if (!active) {
          clearInterval(sendFrames);
          return;
        }
        
        // Check if we have a new frame
        if (lastFrame && lastFrame !== lastSentFrame) {
          try {
            const header = `--${boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: ${lastFrame.length}\r\n\r\n`;
            controller.enqueue(encoder.encode(header));
            controller.enqueue(new Uint8Array(lastFrame));
            controller.enqueue(encoder.encode('\r\n'));
            lastSentFrame = lastFrame;
            activeConnections.set(connectionId, Date.now()); // Update activity timestamp
          } catch {
            // Client disconnected
            active = false;
            clearInterval(sendFrames);
          }
        }
      }, 50); // 20 FPS for better compatibility

      // Store cleanup function
      const cleanup = () => {
        if (!active) return; // Already cleaned up
        active = false;
        clearInterval(sendFrames);
        
        // Remove from tracking
        if (activeConnections.delete(connectionId)) {
          frameSubscribers = Math.max(0, frameSubscribers - 1);
          console.log(`👋 Client ${connectionId} disconnected. Active subscribers: ${frameSubscribers}`);
        }
        
        scheduleFFmpegStop();
      };

      // Attach cleanup to controller
      (controller as { cleanup?: () => void }).cleanup = cleanup;
    },

    cancel() {
      const ctrl = this as { cleanup?: () => void };
      if (ctrl.cleanup) ctrl.cleanup();
    }
  });

  return new Response(stream as unknown as BodyInit, {
    headers: {
      'Content-Type': `multipart/x-mixed-replace; boundary=${boundary}`,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
    },
  });
}




