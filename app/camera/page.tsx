'use client';

import { useState } from 'react';
import { Video, Camera } from 'lucide-react';

export default function CameraTest() {
  const [error, setError] = useState<string>('');
  const [loading, setLoading] = useState(true);

  const handleImageLoad = () => {
    setLoading(false);
    setError('');
  };

  const handleImageError = () => {
    setError('Failed to load video stream');
    setLoading(false);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-950 via-black to-gray-950 p-8">
      <div className="max-w-7xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-4xl font-bold text-white mb-2 flex items-center gap-3">
              <Video className="w-10 h-10 text-amber-400" />
              Live Camera <span className="bg-gradient-to-r from-amber-400 via-yellow-400 to-amber-500 bg-clip-text text-transparent">Video Stream</span>
            </h1>
            <p className="text-white/40">Direct FFmpeg video stream - no file saving!</p>
          </div>
        </div>

        {/* Video Stream Display */}
        <div className="bg-gradient-to-br from-gray-900/50 to-black/50 backdrop-blur-xl rounded-3xl border border-white/10 p-8 mb-6">
          <div className="relative aspect-video bg-black rounded-2xl overflow-hidden border border-white/5">
            {loading && (
              <div className="absolute inset-0 flex items-center justify-center bg-gray-900/50 backdrop-blur-sm z-10">
                <div className="text-center">
                  <Camera className="w-16 h-16 text-amber-400 mx-auto mb-4 animate-pulse" />
                  <p className="text-white/60">Loading video stream...</p>
                </div>
              </div>
            )}
            
            {error ? (
              <div className="absolute inset-0 flex flex-col items-center justify-center bg-red-500/10 z-10">
                <Camera className="w-16 h-16 text-red-400 mb-4" />
                <p className="text-red-400 font-semibold mb-2">Stream Error</p>
                <p className="text-white/60 text-sm max-w-md text-center px-4">{error}</p>
              </div>
            ) : null}
            
            <img 
              src="/api/camera-stream"
              alt="Live camera stream" 
              className="w-full h-full object-contain"
              onLoad={handleImageLoad}
              onError={handleImageError}
            />

            {/* Live Indicator */}
            {!loading && !error && (
              <div className="absolute top-4 left-4 flex items-center gap-2 bg-black/70 backdrop-blur-sm px-3 py-1.5 rounded-full border border-red-500/50">
                <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse" />
                <span className="text-red-500 font-semibold text-xs uppercase tracking-wider">Live Video</span>
              </div>
            )}

            {/* FPS Info */}
            {!loading && !error && (
              <div className="absolute top-4 right-4 bg-black/70 backdrop-blur-sm px-3 py-1.5 rounded-full border border-amber-400/50">
                <span className="text-amber-400 font-semibold text-xs">30 FPS • 1024x768</span>
              </div>
            )}
          </div>
        </div>

        {/* Info Card */}
        <div className="bg-gradient-to-br from-gray-900/50 to-black/50 backdrop-blur-xl rounded-3xl border border-white/10 p-6">
          <div className="flex items-start gap-4">
            <div className="bg-amber-400/10 p-3 rounded-xl">
              <Video className="w-6 h-6 text-amber-400" />
            </div>
            <div>
              <h3 className="text-white font-bold mb-1">Direct FFmpeg Video Stream</h3>
              <p className="text-white/60 text-sm leading-relaxed">
                Real-time 30 FPS video streaming directly from camera using FFmpeg. 
                No files saved - pure video stream from hardware to browser at maximum quality!
              </p>
              <div className="mt-3 flex gap-3 text-xs">
                <span className="px-2 py-1 bg-green-400/10 text-green-400 rounded-lg border border-green-400/20">
                  Device: Webcam C110
                </span>
                <span className="px-2 py-1 bg-blue-400/10 text-blue-400 rounded-lg border border-blue-400/20">
                  1024x768 @ 30 FPS
                </span>
                <span className="px-2 py-1 bg-purple-400/10 text-purple-400 rounded-lg border border-purple-400/20">
                  Direct Stream
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
