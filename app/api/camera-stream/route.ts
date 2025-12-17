/* eslint-disable @typescript-eslint/no-explicit-any */
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
const platform = os.platform();
const isWindows = platform === 'win32';
const isMac = platform === 'darwin';
const isLinux = platform === 'linux';

// Track active connections with timestamps
const activeConnections = new Map<number, { lastActivity: number; controller: ReadableStreamDefaultController | null }>();
let connectionIdCounter = 0;

// Keep-alive ping interval - send heartbeat frames
const KEEPALIVE_INTERVAL = 10000; // 10 seconds
const STALE_THRESHOLD = 35000; // 35 seconds - increased from 30s
const RECONNECT_GRACE_PERIOD = 5000; // 5 seconds grace before stopping FFmpeg

// Cleanup stale connections every 5 seconds (increased from 2s)
setInterval(() => {
  const now = Date.now();
  
  for (const [id, conn] of activeConnections.entries()) {
    if (now - conn.lastActivity > STALE_THRESHOLD) {
      console.log(`🧹 Cleaning up stale connection ${id}`);
      activeConnections.delete(id);
      frameSubscribers = Math.max(0, frameSubscribers - 1);
    }
  }
  
  // If no active connections, schedule FFmpeg stop with grace period
  if (frameSubscribers === 0 && sharedFFmpegProcess && !restartTimeout) {
    scheduleFFmpegStop();
  }
}, 5000);

// Detect webcam device
function detectWebcam(): string | null {
  if (detectedCameraIndex !== null) {
    return detectedCameraIndex;
  }

  console.log(`🔍 Detecting webcam on ${platform}...`);
  
  let result;
  if (isWindows) {
    result = spawnSync('ffmpeg', ['-list_devices', 'true', '-f', 'dshow', '-i', 'dummy'], {
      encoding: 'utf-8'
    });
  } else if (isMac) {
    result = spawnSync('ffmpeg', ['-f', 'avfoundation', '-list_devices', 'true', '-i', ''], {
      encoding: 'utf-8'
    });
  } else { // Linux
    try {
      console.log('🐧 Trying v4l2-ctl to detect webcam...');
      const v4l2Result = spawnSync('v4l2-ctl', ['--list-devices'], { encoding: 'utf-8' });
      
      if (v4l2Result.error) {
        throw v4l2Result.error;
      }

      if (v4l2Result.stdout) {
        const devices = v4l2Result.stdout.split('\n\n');
        const cameraCandidates: { name: string, path: string, priority: number }[] = [];

        for (const device of devices) {
          const lines = device.split('\n').map(l => l.trim());
          if (lines.length < 2) continue;

          const deviceName = lines[0];
          const devicePathLine = lines.find(l => l.startsWith('/dev/video'));

          if (deviceName && devicePathLine) {
            const match = devicePathLine.match(/(\/dev\/video\d+)/);
            if (match) {
              const devicePath = match[1];
              let priority = 0;
              
              const lowerDeviceName = deviceName.toLowerCase();

              if (lowerDeviceName.includes('c110') || lowerDeviceName.includes('logitech')) {
                priority = 3;
              } else if (lowerDeviceName.includes('webcam') && !lowerDeviceName.includes('hp')) {
                priority = 2;
              } else if (lowerDeviceName.includes('usb')) {
                priority = 1;
              }
              
              console.log(`📹 Found device with v4l2-ctl: ${deviceName} at ${devicePath} (Priority: ${priority})`);
              cameraCandidates.push({ name: deviceName, path: devicePath, priority });
            }
          }
        }

        if (cameraCandidates.length > 0) {
          cameraCandidates.sort((a, b) => b.priority - a.priority);
          
          const bestCandidate = cameraCandidates[0];
          detectedCameraIndex = bestCandidate.path;
          detectedCameraName = bestCandidate.name;
          
          console.log(`✅ Selected camera with v4l2-ctl: ${detectedCameraName} (${detectedCameraIndex})`);
          return detectedCameraIndex;
        }
      }
      console.log('⚠️ v4l2-ctl did not find a suitable video device, falling back to ffmpeg.');
    } catch (e: any) {
      console.log('⚠️ v4l2-ctl not found or failed, falling back to ffmpeg detection.');
    }
    
    result = spawnSync('ffmpeg', ['-f', 'v4l2', '-list_devices', 'true', '-i', 'dummy'], {
      encoding: 'utf-8'
    });
  }

  if (result.error) {
    console.error('❌ FFmpeg not found! Please install it.');
    return null;
  }
  
  const output = result.stderr || result.stdout || '';
  
  if (!output) {
    console.warn('⚠️ No output from ffmpeg detection command');
    return null;
  }
  
  if (isWindows) {
    const lines = output.split('\n');
    let fallbackCamera: string | null = null;
    let fallbackCameraName: string | null = null;
    
    for (const line of lines) {
      if (line.includes('"') && line.includes('(video)')) {
        const match = line.match(/"([^"]+)"/);
        if (match) {
          const cameraName = match[1];
          
          if (cameraName.toLowerCase().includes('c110') || 
              cameraName.toLowerCase().includes('logitech')) {
            detectedCameraName = cameraName;
            detectedCameraIndex = `video=${detectedCameraName}`;
            console.log(`🎯 Using Logitech/C110 camera: ${detectedCameraName}`);
            return detectedCameraIndex;
          }
          
          if (!fallbackCamera && 
              cameraName.toLowerCase().includes('webcam') && 
              !cameraName.toLowerCase().includes('hp')) {
            fallbackCamera = `video=${cameraName}`;
            fallbackCameraName = cameraName;
          }
          
          if (!fallbackCamera) {
            fallbackCamera = `video=${cameraName}`;
            fallbackCameraName = cameraName;
          }
        }
      }
    }
    
    if (fallbackCamera) {
      detectedCameraIndex = fallbackCamera;
      detectedCameraName = fallbackCameraName;
      console.log(`✅ Using fallback video device: ${fallbackCameraName}`);
      return detectedCameraIndex;
    }
    
    console.warn('⚠️ Could not detect webcam on Windows');
    return null;
    
  } else if (isMac) {
    const lines = output.split('\n');
    for (const line of lines) {
      const logiMatch = line.match(/\[(\d+)\].*(?:Logitech|C110|C920|C922|Webcam)/i);
      if (logiMatch) {
        detectedCameraIndex = logiMatch[1];
        console.log(`✅ Found Logitech webcam at index: ${detectedCameraIndex}`);
        return detectedCameraIndex;
      }
    }
    
    for (const line of lines) {
      if (line.includes('[') && line.includes(']') && !line.toLowerCase().includes('facetime')) {
        const match = line.match(/\[(\d+)\]/);
        if (match) {
          detectedCameraIndex = match[1];
          console.log(`✅ Found external camera at index: ${detectedCameraIndex}`);
          return detectedCameraIndex;
        }
      }
    }
    
    console.warn('⚠️ Could not auto-detect USB webcam, defaulting to index 1');
    detectedCameraIndex = '1';
    return detectedCameraIndex;
    
  } else { // Linux
    const lines = output.split('\n');
    const cameraCandidates: { name: string, path: string, priority: number }[] = [];

    for (const line of lines) {
      const pathMatch = line.match(/(\/dev\/video\d+)/);
      if (pathMatch) {
        const devicePath = pathMatch[1];
        const nameMatch = line.match(/:\s*(.*)$/);
        const deviceName = nameMatch ? nameMatch[1].trim() : 'Unknown';
        
        let priority = 0;
        const lowerDeviceName = deviceName.toLowerCase();

        if (lowerDeviceName.includes('c110') || lowerDeviceName.includes('logitech')) {
          priority = 3;
        } else if (lowerDeviceName.includes('webcam') && !lowerDeviceName.includes('hp')) {
          priority = 2;
        } else if (lowerDeviceName.includes('usb')) {
          priority = 1;
        }
        
        if (!cameraCandidates.some(c => c.path === devicePath)) {
          cameraCandidates.push({ name: deviceName, path: devicePath, priority });
        }
      }
    }

    if (cameraCandidates.length > 0) {
      cameraCandidates.sort((a, b) => b.priority - a.priority);
      
      const bestCandidate = cameraCandidates[0];
      detectedCameraIndex = bestCandidate.path;
      detectedCameraName = bestCandidate.name;
      
      console.log(`✅ Selected camera: ${detectedCameraName} (${detectedCameraIndex})`);
      return detectedCameraIndex;
    }
    
    console.warn('⚠️ Could not auto-detect webcam, defaulting to /dev/video2');
    detectedCameraIndex = '/dev/video0';
    return detectedCameraIndex;
  }
}

// Start shared FFmpeg process
function startSharedFFmpeg() {
  if (sharedFFmpegProcess) {
    console.log('♻️ FFmpeg already running, skipping start');
    return;
  }
  
  const cameraIndex = detectWebcam();
  if (cameraIndex === null) {
    console.error('❌ No webcam detected!');
    return;
  }
  
  console.log(`🎥 Starting shared FFmpeg process with camera: ${cameraIndex}...`);
  
  let ffmpegArgs: string[];
  
  if (isWindows) {
    let deviceName = cameraIndex;
    if (deviceName.startsWith('video=')) {
      deviceName = deviceName.substring(6);
    }
    
    ffmpegArgs = [
      '-f', 'dshow',
      '-vcodec', 'mjpeg',
      '-video_size', '1024x768',
      '-framerate', '30',
      '-i', `video=${deviceName}`,
      '-f', 'image2pipe',
      '-vcodec', 'copy',
      '-',
    ];
  } else if (isMac) {
    ffmpegArgs = [
      '-f', 'avfoundation',
      '-framerate', '30',
      '-video_size', '1024x768',
      '-i', cameraIndex,
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      '-q:v', '3',
      '-',
    ];
  } else {
    ffmpegArgs = [
      '-f', 'v4l2',
      '-framerate', '30',
      '-video_size', '1024x768',
      '-i', cameraIndex,
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      '-q:v', '3',
      '-',
    ];
  }
  
  sharedFFmpegProcess = spawn('ffmpeg', ffmpegArgs);

  let buffer = Buffer.alloc(0);
  const jpegStart = Buffer.from([0xFF, 0xD8]);
  const jpegEnd = Buffer.from([0xFF, 0xD9]);

  sharedFFmpegProcess.stdout?.on('data', (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk]);

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

      lastFrame = buffer.slice(startIdx, endIdx + 2);
      buffer = buffer.slice(endIdx + 2);
    }
  });

  sharedFFmpegProcess.stderr?.on('data', (data: Buffer) => {
    const msg = data.toString().trim();
    if (msg && 
        !msg.includes('frame=') && 
        !msg.includes('fps=') && 
        !msg.includes('bitrate=') &&
        !msg.includes('speed=') &&
        msg.length > 10 &&
        (msg.toLowerCase().includes('error') || 
         msg.toLowerCase().includes('warning') ||
         msg.toLowerCase().includes('failed'))) {
      console.log('FFmpeg:', msg);
    }
  });

  sharedFFmpegProcess.on('exit', (code) => {
    console.log(`⚠️ FFmpeg exited with code ${code}`);
    sharedFFmpegProcess = null;
    lastFrame = null;
    
    // Auto-restart if still have subscribers
    if (frameSubscribers > 0) {
      console.log('♻️ Auto-restarting FFmpeg for active subscribers...');
      setTimeout(startSharedFFmpeg, 2000);
    }
  });
  
  console.log('✅ FFmpeg started successfully');
}

// Stop FFmpeg when no subscribers (with grace period)
function scheduleFFmpegStop() {
  if (restartTimeout) clearTimeout(restartTimeout);
  
  restartTimeout = setTimeout(() => {
    if (frameSubscribers === 0 && sharedFFmpegProcess) {
      console.log('🛑 No subscribers for 5s, stopping FFmpeg...');
      sharedFFmpegProcess.kill('SIGTERM');
      sharedFFmpegProcess = null;
      lastFrame = null;
    }
    restartTimeout = null;
  }, RECONNECT_GRACE_PERIOD);
}

export async function GET() {
  const boundary = 'FRAME';
  const encoder = new TextEncoder();
  
  // Limit maximum concurrent subscribers
  if (frameSubscribers >= 10) {
    console.warn(`⚠️ Too many subscribers (${frameSubscribers}), rejecting new connection`);
    return new Response('Too many connections', { status: 503 });
  }
  
  // Assign unique ID to this connection
  const connectionId = ++connectionIdCounter;
  activeConnections.set(connectionId, { lastActivity: Date.now(), controller: null });
  
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
    // Wait a bit for FFmpeg to initialize
    await new Promise(resolve => setTimeout(resolve, 500));
  }

  const stream = new ReadableStream({
    async start(controller) {
      let active = true;
      let lastSentFrame: Buffer | null = null;
      let keepaliveInterval: NodeJS.Timeout | null = null;
      
      // Store controller reference for potential cleanup
      const conn = activeConnections.get(connectionId);
      if (conn) {
        conn.controller = controller;
      }
      
      // Send initial frame immediately if available
      if (lastFrame) {
        try {
          const header = `--${boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: ${lastFrame.length}\r\n\r\n`;
          controller.enqueue(encoder.encode(header));
          controller.enqueue(new Uint8Array(lastFrame));
          controller.enqueue(encoder.encode('\r\n'));
          lastSentFrame = lastFrame;
          
          const conn = activeConnections.get(connectionId);
          if (conn) conn.lastActivity = Date.now();
        } catch (err) {
          console.error(`❌ Error sending initial frame to client ${connectionId}:`, err);
          active = false;
        }
      }
      
      // Keep-alive heartbeat - send a comment line periodically
      keepaliveInterval = setInterval(() => {
        if (!active) return;
        
        try {
          // Send a small keep-alive comment (not a frame)
          controller.enqueue(encoder.encode(`--${boundary}\r\n`));
          
          const conn = activeConnections.get(connectionId);
          if (conn) conn.lastActivity = Date.now();
        } catch {
          active = false;
          if (keepaliveInterval) clearInterval(keepaliveInterval);
        }
      }, KEEPALIVE_INTERVAL);
      
      // Frame sending loop - 20 FPS
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
            
            const conn = activeConnections.get(connectionId);
            if (conn) conn.lastActivity = Date.now();
          } catch (err) {
            console.error(`❌ Client ${connectionId} disconnected during frame send`);
            active = false;
            clearInterval(sendFrames);
          }
        }
      }, 50); // 20 FPS

      // Cleanup function
      const cleanup = () => {
        if (!active) return;
        active = false;
        
        if (keepaliveInterval) clearInterval(keepaliveInterval);
        clearInterval(sendFrames);
        
        // Remove from tracking
        if (activeConnections.delete(connectionId)) {
          frameSubscribers = Math.max(0, frameSubscribers - 1);
          console.log(`👋 Client ${connectionId} disconnected. Active subscribers: ${frameSubscribers}`);
        }
        
        // Only schedule stop if no more subscribers
        if (frameSubscribers === 0) {
          scheduleFFmpegStop();
        }
      };

      // Attach cleanup to controller
      (controller as any).cleanup = cleanup;
    },

    cancel() {
      const ctrl = this as any;
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
      'Keep-Alive': 'timeout=60, max=1000',
    },
  });
}