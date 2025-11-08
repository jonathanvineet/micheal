import { spawn } from 'child_process';

export async function GET() {
  const boundary = 'FRAME';
  const encoder = new TextEncoder();
  
  // Stream directly from camera using FFmpeg
  const ffmpeg = spawn('ffmpeg', [
    '-f', 'avfoundation',
    '-framerate', '30',
    '-video_size', '1024x768',
    '-i', '0',
    '-f', 'image2pipe',
    '-vcodec', 'mjpeg',
    '-q:v', '2',
    'pipe:1'
  ]);

  let streamClosed = false;
  let buffer = Buffer.alloc(0);

  const stream = new ReadableStream({
    start(controller) {
      console.log('Starting direct FFmpeg video stream from camera...');
      
      ffmpeg.stdout.on('data', (chunk) => {
        if (streamClosed) return;
        
        buffer = Buffer.concat([buffer, chunk]);
        
        // Look for JPEG markers (FFD8 = start, FFD9 = end)
        let startIdx = 0;
        while (true) {
          const jpegStart = buffer.indexOf(Buffer.from([0xFF, 0xD8]), startIdx);
          if (jpegStart === -1) break;
          
          const jpegEnd = buffer.indexOf(Buffer.from([0xFF, 0xD9]), jpegStart + 2);
          if (jpegEnd === -1) break;
          
          // Extract complete JPEG frame
          const frame = buffer.slice(jpegStart, jpegEnd + 2);
          
          // Send multipart boundary + frame
          const header = `--${boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n`;
          
          try {
            controller.enqueue(encoder.encode(header));
            controller.enqueue(new Uint8Array(frame));
            controller.enqueue(encoder.encode('\r\n'));
          } catch (err) {
            console.error('Enqueue error:', err);
          }
          
          // Remove processed data
          buffer = buffer.slice(jpegEnd + 2);
          startIdx = 0;
        }
      });

      ffmpeg.stderr.on('data', (data) => {
        const msg = data.toString();
        if (!msg.includes('frame=')) {
          console.log('FFmpeg:', msg.trim());
        }
      });

      ffmpeg.on('error', (err) => {
        console.error('FFmpeg error:', err);
        if (!streamClosed) controller.error(err);
      });

      ffmpeg.on('exit', (code) => {
        console.log(`FFmpeg exited with code ${code}`);
        if (!streamClosed) controller.close();
      });
    },

    cancel() {
      console.log('Stream cancelled, killing FFmpeg...');
      streamClosed = true;
      ffmpeg.kill('SIGTERM');
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


