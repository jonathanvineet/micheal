import { spawn, ChildProcess } from 'child_process';

// Shared FFmpeg process
let sharedFFmpegProcess: ChildProcess | null = null;
let lastFrame: Buffer | null = null;
let frameSubscribers = 0;
let restartTimeout: NodeJS.Timeout | null = null;

// Start shared FFmpeg process
function startSharedFFmpeg() {
  if (sharedFFmpegProcess) return;
  
  console.log('🎥 Starting shared FFmpeg process...');
  
  sharedFFmpegProcess = spawn('ffmpeg', [
    '-f', 'avfoundation',
    '-framerate', '30',
    '-video_size', '1024x768',
    '-i', '0',
    '-f', 'image2pipe',
    '-vcodec', 'mjpeg',
    '-q:v', '3',
    '-',
  ]);

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
  
  frameSubscribers++;
  console.log(`📱 Client connected. Active subscribers: ${frameSubscribers}`);
  
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
          } catch (err) {
            // Client disconnected
            active = false;
            clearInterval(sendFrames);
          }
        }
      }, 50); // 20 FPS for better compatibility

      // Store cleanup function
      (controller as any).cleanup = () => {
        active = false;
        clearInterval(sendFrames);
        frameSubscribers--;
        console.log(`👋 Client disconnected. Active subscribers: ${frameSubscribers}`);
        scheduleFFmpegStop();
      };
    },

    cancel() {
      const cleanup = (this as any).cleanup;
      if (cleanup) cleanup();
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




