'use client';

import { useState, useEffect, DragEvent } from 'react';
import { Upload, FolderPlus, Download, Trash2, Folder, File, Home, ChevronRight, Loader2, FileText, FileCode, Film, Music, Archive, Image as ImageIcon, Eye, ArrowLeft, Cloud, CloudRain, CloudSnow, Sun, CloudDrizzle, Wind, Camera, Clock, HardDrive, MessageSquare } from 'lucide-react';

interface FileItem {
  name: string;
  isDirectory: boolean;
  size: number;
  modified: string;
  path: string;
}

interface WeatherData {
  temp: number;
  condition: string;
  location: string;
}

export default function FileManager() {
  const [files, setFiles] = useState<FileItem[]>([]);
  const [currentPath, setCurrentPath] = useState('');
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState('');
  const [uploadPercent, setUploadPercent] = useState(0);
  const [showNewFolderInput, setShowNewFolderInput] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');
  const [dragActive, setDragActive] = useState(false);
  const [previewImage, setPreviewImage] = useState<string | null>(null);
  const [weather, setWeather] = useState<WeatherData>({ temp: 22, condition: 'Clear', location: 'San Francisco' });
  const [cameraUrl, setCameraUrl] = useState('');
  const [recentFiles, setRecentFiles] = useState<FileItem[]>([]);
  const [storageUsed, setStorageUsed] = useState(0);
  const [storageTotal, setStorageTotal] = useState(100);
  const [isStorageExpanded, setIsStorageExpanded] = useState(false);
  const [todos, setTodos] = useState<string[]>([]);
  const [newTodo, setNewTodo] = useState('');
  const [showTodoInput, setShowTodoInput] = useState(false);
  const [currentTime, setCurrentTime] = useState(new Date());

  // Update time every second
  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  // Helper function to get file icon based on extension
  const getFileIcon = (fileName: string) => {
    const ext = fileName.toLowerCase().split('.').pop();
    const iconProps = { size: 24, className: "text-[#ffd700]" };
    
    // Image files
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico'].includes(ext || '')) {
      return <ImageIcon {...iconProps} />;
    }
    // Video files
    if (['mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv', 'webm'].includes(ext || '')) {
      return <Film {...iconProps} />;
    }
    // Audio files
    if (['mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'].includes(ext || '')) {
      return <Music {...iconProps} />;
    }
    // Code files
    if (['js', 'jsx', 'ts', 'tsx', 'py', 'java', 'cpp', 'c', 'cs', 'php', 'rb', 'go', 'rs', 'swift'].includes(ext || '')) {
      return <FileCode {...iconProps} />;
    }
    // Document files
    if (['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt'].includes(ext || '')) {
      return <FileText {...iconProps} />;
    }
    // Archive files
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2'].includes(ext || '')) {
      return <Archive {...iconProps} />;
    }
    // Default file icon
    return <File {...iconProps} />;
  };

  // Check if file is an image
  const isImageFile = (fileName: string) => {
    const ext = fileName.toLowerCase().split('.').pop();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp'].includes(ext || '');
  };

  // Handle image preview
  const handleImagePreview = (file: FileItem) => {
    if (isImageFile(file.name)) {
      const imagePath = `/api/download?path=${encodeURIComponent(file.path)}`;
      setPreviewImage(imagePath);
    }
  };

  // Debounced progress update for better performance
  const updateProgress = (percent: number, message?: string) => {
    requestAnimationFrame(() => {
      setUploadPercent(percent);
      if (message) setUploadProgress(message);
    });
  };

  useEffect(() => {
    loadFiles();
  }, [currentPath]);

  const loadFiles = async () => {
    setLoading(true);
    try {
      const response = await fetch(`/api/files?path=${encodeURIComponent(currentPath)}`);
      const data = await response.json();
      if (data.files) {
        setFiles(data.files);
      }
    } catch (error) {
      console.error('Error loading files:', error);
      alert('Failed to load files');
    } finally {
      setLoading(false);
    }
  };

  const handleFileUpload = async (file: File, relativePath?: string) => {
    setUploading(true);
    setUploadProgress(`Preparing to upload ${file.name}...`);
    setUploadPercent(5);
    
    await new Promise(resolve => setTimeout(resolve, 100));
    
    setUploadProgress(`Reading file: ${file.name}...`);
    setUploadPercent(10);
    
    const formData = new FormData();
    const fileKey = 'file-0';
    formData.append(fileKey, file);
    if (relativePath) {
      formData.append('path-0', relativePath);
    }
    formData.append('path', currentPath);

    setUploadProgress(`Uploading ${file.name}...`);
    setUploadPercent(20);

    try {
      // Simulate progress for single file
      let currentProgress = 20;
      const progressInterval = setInterval(() => {
        currentProgress += 8;
        if (currentProgress >= 85) {
          clearInterval(progressInterval);
          setUploadProgress(`Processing ${file.name}...`);
          setUploadPercent(85);
        } else {
          setUploadPercent(currentProgress);
        }
      }, 150);

      const response = await fetch('/api/files', {
        method: 'POST',
        body: formData,
      });

      clearInterval(progressInterval);
      setUploadProgress('Finalizing upload...');
      setUploadPercent(95);

      const data = await response.json();
      if (data.success) {
        if (data.compressed) {
          setUploadProgress(`File compressed and saved (${data.totalSize})`);
          setUploadPercent(100);
          await new Promise(resolve => setTimeout(resolve, 1500));
        } else {
          setUploadProgress('Upload complete!');
          setUploadPercent(100);
          await new Promise(resolve => setTimeout(resolve, 800));
        }
        loadFiles();
        return true;
      } else {
        alert(data.error || 'Upload failed');
        return false;
      }
    } catch (error) {
      console.error('Error uploading file:', error);
      alert('Failed to upload file');
      return false;
    } finally {
      setUploading(false);
      setUploadProgress('');
      setUploadPercent(0);
    }
  };

  const handleMultipleFilesUpload = async (files: FileList) => {
    setUploading(true);
    const totalFiles = files.length;
    const BATCH_SIZE = 20; // Upload 20 files per batch
    const batches: File[][] = [];
    
    // Split files into batches
    const fileArray = Array.from(files);
    for (let i = 0; i < fileArray.length; i += BATCH_SIZE) {
      batches.push(fileArray.slice(i, i + BATCH_SIZE));
    }
    
    updateProgress(5, `Preparing ${totalFiles} file${totalFiles > 1 ? 's' : ''}...`);
    
    try {
      let uploadedFiles = 0;
      
      // Process batches sequentially
      for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex];
        const isLastBatch = batchIndex === batches.length - 1;
        
        updateProgress(
          10 + (batchIndex / batches.length) * 80,
          `Uploading batch ${batchIndex + 1}/${batches.length} (${batch.length} files)...`
        );
        
        const formData = new FormData();
        formData.append('path', currentPath);
        formData.append('batchIndex', batchIndex.toString());
        formData.append('totalBatches', batches.length.toString());
        
        batch.forEach((file, idx) => {
          formData.append(`file-${idx}`, file);
        });
        
        const response = await fetch('/api/upload-batch', {
          method: 'POST',
          body: formData,
        });
        
        const data = await response.json();
        if (!data.success) {
          throw new Error(data.error || 'Upload failed');
        }
        
        uploadedFiles += batch.length;
        updateProgress(
          10 + (uploadedFiles / totalFiles) * 85,
          `Uploaded ${uploadedFiles}/${totalFiles} files...`
        );
      }
      
      updateProgress(100, 'All files uploaded successfully!');
      await new Promise(resolve => setTimeout(resolve, 1000));
      loadFiles();
    } catch (error) {
      console.error('Error uploading files:', error);
      alert('Failed to upload files');
    } finally {
      setUploading(false);
      setUploadProgress('');
      setUploadPercent(0);
    }
  };

  // OLD CHUNKED VERSION REPLACED ABOVE
  const handleMultipleFilesUpload_OLD = async (files: FileList) => {
    setUploading(true);
    setUploadProgress(`Preparing ${files.length} file${files.length > 1 ? 's' : ''}...`);
    setUploadPercent(5);
    
    await new Promise(resolve => setTimeout(resolve, 50));
    
    const formData = new FormData();
    formData.append('path', currentPath);
    
    let fileIndex = 0;
    let totalSize = 0;
    
    setUploadProgress(`Reading ${files.length} file${files.length > 1 ? 's' : ''}...`);
    setUploadPercent(10);
    
    // Process files in chunks to avoid blocking
    const CHUNK_SIZE = 10;
    const totalFiles = files.length;
    
    for (let i = 0; i < totalFiles; i += CHUNK_SIZE) {
      const chunk = Math.min(CHUNK_SIZE, totalFiles - i);
      
      // Process chunk
      for (let j = 0; j < chunk && (i + j) < totalFiles; j++) {
        const file = files[i + j];
        totalSize += file.size;
        const fileKey = `file-${fileIndex}`;
        formData.append(fileKey, file);
        
        // Extract relative path from webkitRelativePath if available
        if ((file as any).webkitRelativePath) {
          formData.append(`path-${fileIndex}`, (file as any).webkitRelativePath);
        } else {
          formData.append(`path-${fileIndex}`, file.name);
        }
        fileIndex++;
      }
      
      // Update progress
      const prepProgress = 10 + Math.floor(((i + chunk) / totalFiles) * 15);
      setUploadPercent(prepProgress);
      setUploadProgress(`Processing file ${Math.min(i + chunk, totalFiles)} of ${totalFiles}...`);
      
      // Yield to browser to keep UI responsive
      await new Promise(resolve => requestAnimationFrame(() => resolve(undefined)));
    }

    setUploadProgress(`Uploading ${files.length} file${files.length > 1 ? 's' : ''}...`);
    setUploadPercent(30);

    try {
      // Simulate upload progress
      let currentProgress = 30;
      const progressInterval = setInterval(() => {
        currentProgress += 6;
        if (currentProgress >= 85) {
          clearInterval(progressInterval);
          setUploadProgress('Processing uploaded files...');
          setUploadPercent(85);
        } else {
          setUploadPercent(currentProgress);
        }
      }, 200);

      const response = await fetch('/api/files', {
        method: 'POST',
        body: formData,
      });

      clearInterval(progressInterval);
      setUploadProgress('Saving files...');
      setUploadPercent(95);

      const data = await response.json();
      if (data.success) {
        if (data.compressed) {
          setUploadProgress(`${files.length} files compressed and saved (${data.totalSize})`);
          setUploadPercent(100);
          await new Promise(resolve => setTimeout(resolve, 1500));
        } else {
          setUploadProgress('Upload complete!');
          setUploadPercent(100);
          await new Promise(resolve => setTimeout(resolve, 800));
        }
        loadFiles();
        alert(data.message || 'Files uploaded successfully!');
      } else {
        alert(data.error || 'Upload failed');
      }
    } catch (error) {
      console.error('Error uploading files:', error);
      alert('Failed to upload files');
    } finally {
      setUploading(false);
      setUploadProgress('');
      setUploadPercent(0);
    }
  };

  const handleFileInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files && files.length > 0) {
      if (files.length === 1) {
        handleFileUpload(files[0]);
      } else {
        handleMultipleFilesUpload(files);
      }
    }
  };

  const handleFolderInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files && files.length > 0) {
      handleMultipleFilesUpload(files);
    }
  };

  const handleCreateFolder = async () => {
    if (!newFolderName.trim()) {
      alert('Please enter a folder name');
      return;
    }

    try {
      const response = await fetch('/api/folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          folderName: newFolderName,
          currentPath,
        }),
      });

      const data = await response.json();
      if (data.success) {
        setNewFolderName('');
        setShowNewFolderInput(false);
        loadFiles();
        alert(`Folder "${newFolderName}" created successfully!`);
      } else {
        alert(data.error || 'Failed to create folder');
      }
    } catch (error) {
      console.error('Error creating folder:', error);
      alert('Failed to create folder');
    }
  };

  const handleDelete = async (filePath: string, name: string) => {
    if (!confirm(`Are you sure you want to delete "${name}"?`)) {
      return;
    }

    try {
      const response = await fetch('/api/files', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ filePath }),
      });

      const data = await response.json();
      if (data.success) {
        loadFiles();
        alert(`"${name}" deleted successfully!`);
      } else {
        alert(data.error || 'Failed to delete');
      }
    } catch (error) {
      console.error('Error deleting:', error);
      alert('Failed to delete');
    }
  };

  const handleDownload = (filePath: string, name: string) => {
    const link = document.createElement('a');
    link.href = `/api/download?path=${encodeURIComponent(filePath)}`;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const navigateToFolder = (folderPath: string) => {
    setCurrentPath(folderPath);
  };

  const navigateBack = () => {
    const pathParts = currentPath.split('/').filter(Boolean);
    pathParts.pop();
    setCurrentPath(pathParts.join('/'));
  };

  const navigateHome = () => {
    setCurrentPath('');
  };

  const formatFileSize = (bytes: number) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString();
  };

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = async (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    
    if (e.dataTransfer.items) {
      const items = Array.from(e.dataTransfer.items);
      const entries: any[] = [];
      
      for (const item of items) {
        const entry = item.webkitGetAsEntry?.();
        if (entry) {
          entries.push(entry);
        }
      }

      if (entries.length > 0) {
        await processDroppedEntries(entries);
      }
    } else if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      handleMultipleFilesUpload(e.dataTransfer.files);
    }
  };

  const processDroppedEntries = async (entries: any[]) => {
    setUploading(true);
    updateProgress(5, 'Analyzing dropped items...');
    
    const files: { file: File; path: string }[] = [];
    
    updateProgress(10, 'Reading folder structure...');
    
    const readEntry = async (entry: any, basePath = ''): Promise<void> => {
      if (entry.isFile) {
        return new Promise((resolve) => {
          entry.file((file: File) => {
            const relativePath = basePath ? `${basePath}/${file.name}` : file.name;
            files.push({ file, path: relativePath });
            resolve();
          });
        });
      } else if (entry.isDirectory) {
        const dirReader = entry.createReader();
        return new Promise((resolve) => {
          dirReader.readEntries(async (entries: any[]) => {
            const newBasePath = basePath ? `${basePath}/${entry.name}` : entry.name;
            
            // Process directory entries in batches
            const BATCH_SIZE = 10;
            for (let i = 0; i < entries.length; i += BATCH_SIZE) {
              const batch = entries.slice(i, i + BATCH_SIZE);
              await Promise.all(batch.map(e => readEntry(e, newBasePath)));
            }
            resolve();
          });
        });
      }
    };

    for (const entry of entries) {
      await readEntry(entry);
    }

    if (files.length === 0) {
      setUploading(false);
      alert('No files found');
      return;
    }

    updateProgress(20, `Found ${files.length} file${files.length > 1 ? 's' : ''}. Starting upload...`);
    
    const BATCH_SIZE = 20; // Upload 20 files per batch
    const totalFiles = files.length;
    const batches: typeof files[] = [];
    
    // Split files into batches
    for (let i = 0; i < files.length; i += BATCH_SIZE) {
      batches.push(files.slice(i, i + BATCH_SIZE));
    }

    try {
      let uploadedFiles = 0;
      
      // Process batches sequentially
      for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex];
        
        updateProgress(
          20 + (batchIndex / batches.length) * 70,
          `Uploading batch ${batchIndex + 1}/${batches.length} (${batch.length} files)...`
        );
        
        const formData = new FormData();
        formData.append('path', currentPath);
        formData.append('batchIndex', batchIndex.toString());
        formData.append('totalBatches', batches.length.toString());
        
        batch.forEach((item, idx) => {
          formData.append(`file-${idx}`, item.file);
          formData.append(`path-${idx}`, item.path);
        });
        
        const response = await fetch('/api/upload-batch', {
          method: 'POST',
          body: formData,
        });
        
        const data = await response.json();
        if (!data.success) {
          throw new Error(data.error || 'Upload failed');
        }
        
        uploadedFiles += batch.length;
        updateProgress(
          20 + (uploadedFiles / totalFiles) * 75,
          `Uploaded ${uploadedFiles}/${totalFiles} files...`
        );
      }
      
      updateProgress(100, `All ${totalFiles} files uploaded successfully!`);
      await new Promise(resolve => setTimeout(resolve, 1000));
      loadFiles();
    } catch (error) {
      console.error('Error uploading files:', error);
      alert('Failed to upload files');
    } finally {
      setUploading(false);
      setUploadProgress('');
      setUploadPercent(0);
    }
  };

  const pathSegments = currentPath.split('/').filter(Boolean);

  // Get weather icon
  const getWeatherIcon = () => {
    switch (weather.condition.toLowerCase()) {
      case 'rain': return <CloudRain className="w-12 h-12 text-blue-400" />;
      case 'snow': return <CloudSnow className="w-12 h-12 text-blue-200" />;
      case 'cloudy': return <Cloud className="w-12 h-12 text-gray-400" />;
      case 'drizzle': return <CloudDrizzle className="w-12 h-12 text-blue-300" />;
      case 'windy': return <Wind className="w-12 h-12 text-gray-500" />;
      default: return <Sun className="w-12 h-12 text-yellow-400" />;
    }
  };

  // Calculate storage percentage
  useEffect(() => {
    const totalSize = files.reduce((sum, file) => !file.isDirectory ? sum + file.size : sum, 0);
    setStorageUsed(totalSize / (1024 * 1024 * 1024)); // Convert to GB
    
    // Get recent files (last 5 uploaded)
    const sorted = [...files].filter(f => !f.isDirectory).sort((a, b) => 
      new Date(b.modified).getTime() - new Date(a.modified).getTime()
    );
    setRecentFiles(sorted.slice(0, 5));
  }, [files]);

  return (
    <div className="min-h-screen bg-black">
      <div className="container mx-auto px-6 py-8 max-w-7xl">
        
        {/* Modern Dashboard */}
        <div className="mb-8">
          {/* Top Bar - Greeting & Time */}
          <div className="flex items-center justify-between mb-8">
            <div>
              <h1 className="text-6xl font-black mb-2">
                <span className="text-white">Hello, </span>
                <span className="bg-gradient-to-r from-amber-400 via-yellow-400 to-amber-500 bg-clip-text text-transparent">
                  Batman
                </span>
              </h1>
              <p className="text-gray-500 text-lg">{currentTime.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}</p>
            </div>
            <div className="text-right">
              <div className="text-5xl font-black text-white mb-1">
                {currentTime.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
              </div>
              <p className="text-gray-500 text-sm uppercase tracking-wider">{currentTime.toLocaleTimeString('en-US', { hour12: true }).split(' ')[1]}</p>
            </div>
          </div>

          {/* Main Dashboard Grid */}
          <div className="grid grid-cols-12 gap-6">
            
            {/* Weather Card */}
            <div className="col-span-12 md:col-span-4 bg-gradient-to-br from-blue-500/10 to-purple-500/10 backdrop-blur-xl rounded-3xl border border-white/10 p-8 hover:border-amber-400/50 transition-all duration-300">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-white/60 uppercase text-sm font-bold tracking-widest">Weather</h3>
                {getWeatherIcon()}
              </div>
              <div className="flex items-baseline gap-2 mb-4">
                <span className="text-7xl font-black text-white">{weather.temp}</span>
                <span className="text-3xl font-light text-white/60">°C</span>
              </div>
              <p className="text-xl text-white/80 font-medium mb-1">{weather.condition}</p>
              <p className="text-white/50 text-sm">{weather.location}</p>
            </div>

            {/* USB Camera Feed */}
                      {/* Camera */}
          <div className="col-span-8 bg-gradient-to-br from-gray-900/50 to-black/50 backdrop-blur-xl rounded-3xl border border-white/10 p-6">
            <h3 className="text-white font-bold mb-4">Live Camera Feed</h3>
            <div className="relative aspect-video bg-black rounded-2xl overflow-hidden border border-white/5">
              <img 
                src="/api/camera-stream"
                alt="Live camera stream" 
                className="w-full h-full object-contain"
              />
              {/* Live indicator */}
              <div className="absolute top-4 left-4 flex items-center gap-2 bg-black/70 backdrop-blur-sm px-3 py-1.5 rounded-full border border-red-500/50">
                <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse" />
                <span className="text-red-500 font-semibold text-xs uppercase">Live 30 FPS</span>
              </div>
            </div>
          </div>

            {/* Things To Do */}
            <div className="col-span-12 md:col-span-6 bg-gradient-to-br from-amber-500/10 to-orange-500/10 backdrop-blur-xl rounded-3xl border border-white/10 p-8 hover:border-amber-400/50 transition-all duration-300">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-white/60 uppercase text-sm font-bold tracking-widest">Things To Do</h3>
                <button
                  onClick={() => setShowTodoInput(!showTodoInput)}
                  className="w-10 h-10 bg-amber-400 hover:bg-amber-500 text-black rounded-full flex items-center justify-center transition-all duration-300 hover:scale-110"
                >
                  <span className="text-xl font-bold">+</span>
                </button>
              </div>

              {showTodoInput && (
                <div className="mb-4">
                  <input
                    type="text"
                    value={newTodo}
                    onChange={(e) => setNewTodo(e.target.value)}
                    onKeyPress={(e) => {
                      if (e.key === 'Enter' && newTodo.trim()) {
                        setTodos([...todos, newTodo.trim()]);
                        setNewTodo('');
                        setShowTodoInput(false);
                      }
                    }}
                    placeholder="What needs to be done?"
                    className="w-full bg-black/30 border border-white/20 rounded-xl px-4 py-3 text-white placeholder-white/40 focus:border-amber-400 focus:outline-none transition-all"
                    autoFocus
                  />
                </div>
              )}

              <div className="space-y-3 max-h-[300px] overflow-y-auto pr-2">
                {todos.length === 0 ? (
                  <div className="text-center py-12">
                    <p className="text-white/30 text-sm">No tasks yet. Add one to get started.</p>
                  </div>
                ) : (
                  todos.map((todo, index) => (
                    <div
                      key={index}
                      className="flex items-center gap-3 p-4 bg-black/20 border border-white/10 rounded-xl hover:border-amber-400/50 transition-all group"
                    >
                      <div className="w-5 h-5 rounded-full border-2 border-white/30 group-hover:border-amber-400 transition-all"></div>
                      <p className="text-white flex-1">{todo}</p>
                      <button
                        onClick={() => setTodos(todos.filter((_, i) => i !== index))}
                        className="opacity-0 group-hover:opacity-100 w-8 h-8 bg-red-500/20 hover:bg-red-500 text-red-400 hover:text-white rounded-lg flex items-center justify-center transition-all"
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Storage Stats */}
            <div className="col-span-12 md:col-span-6 bg-gradient-to-br from-green-500/10 to-emerald-500/10 backdrop-blur-xl rounded-3xl border border-white/10 p-8 hover:border-amber-400/50 transition-all duration-300">
              <div className="flex items-center gap-3 mb-6">
                <HardDrive className="w-6 h-6 text-emerald-400" />
                <h3 className="text-white/60 uppercase text-sm font-bold tracking-widest">Storage</h3>
              </div>
              
              <div className="mb-6">
                <div className="flex justify-between items-baseline mb-3">
                  <span className="text-4xl font-black text-white">{storageUsed.toFixed(2)}</span>
                  <span className="text-white/40 text-sm">GB / {storageTotal} GB</span>
                </div>
                <div className="w-full h-3 bg-black/30 rounded-full overflow-hidden">
                  <div 
                    className="h-full bg-gradient-to-r from-emerald-400 to-green-500 rounded-full transition-all duration-1000"
                    style={{ width: `${Math.min((storageUsed / storageTotal) * 100, 100)}%` }}
                  ></div>
                </div>
              </div>

              <div className="space-y-2">
                <h4 className="text-white/40 text-xs uppercase tracking-wider mb-3">Recent Files</h4>
                {recentFiles.slice(0, 3).map((file, index) => (
                  <div 
                    key={index}
                    className="flex items-center gap-3 p-3 bg-black/20 border border-white/5 rounded-xl hover:border-emerald-400/30 transition-all cursor-pointer"
                    onClick={() => handleImagePreview(file)}
                  >
                    <div className="w-10 h-10 bg-black/30 rounded-lg overflow-hidden flex items-center justify-center">
                      {isImageFile(file.name) ? (
                        <img 
                          src={`/api/download?path=${encodeURIComponent(file.path)}`}
                          alt={file.name}
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        getFileIcon(file.name)
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-white text-sm truncate">{file.name}</p>
                      <p className="text-white/40 text-xs">{formatFileSize(file.size)}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Cloud Storage Section */}
        <div className="mt-8">
          {!isStorageExpanded ? (
            /* Storage Preview */
            <div 
              className="bg-gradient-to-br from-gray-900/50 to-black/50 backdrop-blur-xl rounded-3xl border border-white/10 p-8 hover:border-amber-400/50 transition-all duration-300 cursor-pointer"
              onClick={() => setIsStorageExpanded(true)}
            >
              <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-4">
                  <div className="w-14 h-14 bg-gradient-to-br from-amber-400 to-yellow-500 rounded-2xl flex items-center justify-center">
                    <HardDrive size={28} className="text-black" />
                  </div>
                  <div>
                    <h2 className="text-3xl font-black text-white mb-1">Cloud Storage</h2>
                    <p className="text-white/40 text-sm">Click to expand and manage files</p>
                  </div>
                </div>
                <Eye className="w-8 h-8 text-amber-400 animate-pulse" />
              </div>

              {loading ? (
                <div className="text-center py-8">
                  <Loader2 className="animate-spin h-10 w-10 text-amber-400 mx-auto" />
                </div>
              ) : files.length === 0 ? (
                <div className="text-center py-12">
                  <Folder size={48} className="text-white/20 mx-auto mb-3" />
                  <p className="text-white/40">No files yet</p>
                </div>
              ) : (
                <div className="grid grid-cols-4 md:grid-cols-6 gap-4">
                  {files.slice(0, 12).map((file, index) => (
                    <div key={index} className="group">
                      <div className="aspect-square bg-black/50 rounded-2xl overflow-hidden mb-2 flex items-center justify-center border border-white/10 group-hover:border-amber-400/50 transition-all">
                        {file.isDirectory ? (
                          <Folder size={32} className="text-amber-400" />
                        ) : isImageFile(file.name) ? (
                          <img 
                            src={`/api/download?path=${encodeURIComponent(file.path)}`}
                            alt={file.name}
                            className="w-full h-full object-cover"
                            loading="lazy"
                          />
                        ) : (
                          <div className="scale-75">
                            {getFileIcon(file.name)}
                          </div>
                        )}
                      </div>
                      <p className="text-xs text-white/60 truncate text-center">{file.name}</p>
                    </div>
                  ))}
                  {files.length > 12 && (
                    <div className="aspect-square bg-black/50 rounded-2xl flex items-center justify-center border border-dashed border-amber-400/30">
                      <div className="text-center">
                        <p className="text-2xl font-bold text-amber-400">+{files.length - 12}</p>
                        <p className="text-xs text-white/40">more</p>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          ) : (
            /* Expanded Storage - Full Manager */
            <div className="bg-gradient-to-br from-gray-900/50 to-black/50 backdrop-blur-xl rounded-3xl border border-white/10 overflow-hidden">
              
              {/* Header */}
              <div className="bg-black/50 border-b border-white/10 p-6">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-gradient-to-br from-amber-400 to-yellow-500 rounded-2xl flex items-center justify-center">
                      <HardDrive size={24} className="text-black" />
                    </div>
                    <div>
                      <h2 className="text-2xl font-black text-white">Cloud Storage</h2>
                      <p className="text-white/60 text-sm">
                        {storageUsed.toFixed(2)} GB / {storageTotal} GB
                      </p>
                    </div>
                  </div>
                  <button 
                    onClick={() => setIsStorageExpanded(false)}
                    className="px-4 py-2 bg-white/5 hover:bg-white/10 text-white rounded-xl border border-white/10 hover:border-amber-400/50 transition-all text-sm font-medium"
                  >
                    <ArrowLeft size={16} className="inline mr-2" />Collapse
                  </button>
                </div>
              </div>              {/* Upload Progress */}
              {uploading && (
                <div className="bg-black/50 border-b border-white/10 p-4">
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-amber-400 font-semibold text-sm">{uploadProgress}</span>
                      <span className="text-amber-400 font-bold">{uploadPercent}%</span>
                    </div>
                    <div className="h-2 bg-white/5 rounded-full overflow-hidden">
                      <div 
                        className="h-full bg-gradient-to-r from-amber-400 to-yellow-500 transition-all duration-300"
                        style={{ width: `${uploadPercent}%` }}
                      ></div>
                    </div>
                  </div>
                </div>
              )}

              {/* Toolbar */}
              <div className="border-b border-white/10 bg-black/30 p-4">
                <div className="flex flex-wrap gap-2">
                  <button onClick={navigateHome} className="px-3 py-1.5 bg-amber-400/10 hover:bg-amber-400/20 text-amber-400 rounded-xl border border-amber-400/30 hover:border-amber-400/50 transition-all text-sm font-medium" disabled={uploading}>
                    <Home size={14} className="inline mr-1.5" />Home
                  </button>
                  
                  {currentPath && (
                    <button onClick={navigateBack} className="px-3 py-1.5 bg-white/5 hover:bg-white/10 text-white rounded-xl border border-white/10 hover:border-white/20 transition-all text-sm font-medium" disabled={uploading}>
                      <ArrowLeft size={14} className="inline mr-1.5" />Back
                    </button>
                  )}

                  <label className={`px-3 py-1.5 bg-blue-500/10 hover:bg-blue-500/20 text-blue-400 rounded-xl border border-blue-400/30 hover:border-blue-400/50 transition-all text-sm font-medium ${uploading ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}>
                    <Upload size={14} className="inline mr-1.5" />Upload
                    <input type="file" onChange={handleFileInputChange} className="hidden" disabled={uploading} />
                  </label>

                  <button
                    onClick={() => setShowNewFolderInput(!showNewFolderInput)}
                    className="px-3 py-1.5 bg-purple-500/10 hover:bg-purple-500/20 text-purple-400 rounded-xl border border-purple-400/30 hover:border-purple-400/50 transition-all text-sm font-medium"
                    disabled={uploading}
                  >
                    <FolderPlus size={14} className="inline mr-1.5" />New Folder
                  </button>
                </div>

                {/* New Folder Input */}
                {showNewFolderInput && (
                  <div className="mt-3 flex gap-2">
                    <input
                      type="text"
                      value={newFolderName}
                      onChange={(e) => setNewFolderName(e.target.value)}
                      onKeyPress={(e) => e.key === 'Enter' && handleCreateFolder()}
                      placeholder="Folder name..."
                      className="flex-1 bg-black/50 border border-white/20 rounded-xl px-4 py-2 text-white text-sm focus:border-amber-400/50 focus:outline-none placeholder:text-white/40"
                    />
                    <button onClick={handleCreateFolder} className="px-4 py-2 bg-amber-400/10 hover:bg-amber-400/20 text-amber-400 rounded-xl border border-amber-400/30 hover:border-amber-400/50 transition-all text-sm font-medium">Create</button>
                    <button onClick={() => { setShowNewFolderInput(false); setNewFolderName(''); }} className="px-4 py-2 bg-white/5 hover:bg-white/10 text-white rounded-xl border border-white/10 hover:border-white/20 transition-all text-sm font-medium">Cancel</button>
                  </div>
                )}
              </div>

              {/* Breadcrumb */}
              <div className="bg-black/30 border-b border-white/10 p-4">
                <div className="flex items-center gap-2 text-sm">
                  <Home size={14} className="text-amber-400" />
                  <button onClick={navigateHome} className="text-white/60 hover:text-amber-400 transition-colors font-medium">uploads</button>
                  {pathSegments.map((segment, index) => (
                    <span key={index} className="flex items-center gap-2">
                      <span className="text-white/30">/</span>
                      <button
                        onClick={() => navigateToFolder(pathSegments.slice(0, index + 1).join('/'))}
                        className="text-white/60 hover:text-amber-400 transition-colors font-medium"
                      >
                        {segment}
                      </button>
                    </span>
                  ))}
                </div>
              </div>

              {/* Drop Zone & File List - Grid Layout */}
              <div
                onDragEnter={handleDrag}
                onDragLeave={handleDrag}
                onDragOver={handleDrag}
                onDrop={handleDrop}
                className={`relative ${dragActive && !uploading ? 'bg-amber-400/5' : ''}`}
              >
                {dragActive && !uploading && (
                  <div className="absolute inset-0 bg-gradient-to-br from-amber-400/20 to-yellow-500/20 flex items-center justify-center z-10 border-4 border-dashed border-amber-400 m-4 rounded-2xl backdrop-blur-sm">
                    <div className="text-center p-8 bg-black/90 rounded-2xl border border-amber-400/50">
                      <Upload size={48} className="mx-auto text-amber-400 mb-3 animate-pulse" />
                      <p className="text-xl font-bold text-amber-400 mb-1">Drop to Upload</p>
                      <p className="text-white/60 text-sm">Files will be secured</p>
                    </div>
                  </div>
                )}

                <div className="p-6 max-h-[700px] overflow-y-auto">
                  {loading ? (
                    <div className="text-center py-12">
                      <Loader2 className="animate-spin h-12 w-12 text-amber-400 mx-auto mb-3" />
                      <p className="text-amber-400 font-semibold">Loading...</p>
                    </div>
                  ) : files.length === 0 ? (
                    <div className="text-center py-12">
                      <Folder size={48} className="text-white/20 mx-auto mb-3" />
                      <p className="text-white/40">No files yet</p>
                      <p className="text-xs text-white/30 mt-2">Upload files or create folders to begin</p>
                    </div>
                  ) : (
                    <div className="grid grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                      {files.map((file, index) => (
                        <div key={index} className="group relative">
                          {/* File/Folder Icon */}
                          <div 
                            className="aspect-square bg-black/50 rounded-2xl overflow-hidden mb-2 flex items-center justify-center border border-white/10 group-hover:border-amber-400/50 transition-all cursor-pointer"
                            onClick={() => file.isDirectory ? navigateToFolder(file.path) : handleImagePreview(file)}
                          >
                            {file.isDirectory ? (
                              <Folder size={40} className="text-amber-400" />
                            ) : isImageFile(file.name) ? (
                              <img 
                                src={`/api/download?path=${encodeURIComponent(file.path)}`}
                                alt={file.name}
                                className="w-full h-full object-cover"
                                loading="lazy"
                              />
                            ) : (
                              <div className="scale-90">
                                {getFileIcon(file.name)}
                              </div>
                            )}
                          </div>
                          
                          {/* File Name */}
                          <p className="text-xs text-white truncate text-center mb-1 px-1 font-medium">{file.name}</p>
                          
                          {/* File Size/Type */}
                          <p className="text-xs text-white/40 text-center">
                            {file.isDirectory ? 'Folder' : formatFileSize(file.size)}
                          </p>

                          {/* Action Buttons - Show on Hover */}
                          <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                            {!file.isDirectory && (
                              <button
                                onClick={(e) => { e.stopPropagation(); handleDownload(file.path, file.name); }}
                                className="p-1.5 bg-amber-400 text-black rounded-lg hover:bg-amber-500 transition-all shadow-lg"
                                title="Download"
                              >
                                <Download size={14} />
                              </button>
                            )}
                            <button
                              onClick={(e) => { e.stopPropagation(); handleDelete(file.path, file.name); }}
                              className="p-1.5 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-all shadow-lg"
                              title="Delete"
                            >
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Image Preview Modal */}
      {previewImage && (
        <div 
          className="fixed inset-0 bg-black/95 backdrop-blur-xl z-50 flex items-center justify-center p-4"
          onClick={() => setPreviewImage(null)}
        >
          <div className="relative max-w-7xl max-h-[90vh] w-full h-full flex items-center justify-center">
            <button
              onClick={() => setPreviewImage(null)}
              className="absolute top-4 right-4 p-3 bg-amber-400 hover:bg-amber-500 text-black rounded-2xl transition-all z-10 font-bold shadow-lg"
            >
              ✕ Close
            </button>
            <img 
              src={previewImage} 
              alt="Preview" 
              className="max-w-full max-h-full object-contain rounded-2xl shadow-2xl"
              onClick={(e) => e.stopPropagation()}
            />
          </div>
        </div>
      )}
    </div>
  );
}

