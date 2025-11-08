'use client';

import { useState, useEffect, DragEvent } from 'react';
import { Upload, FolderPlus, Download, Trash2, Folder, File, Home, ChevronRight, Loader2, FileText, FileCode, Film, Music, Archive, Image as ImageIcon, Eye, ArrowLeft } from 'lucide-react';

interface FileItem {
  name: string;
  isDirectory: boolean;
  size: number;
  modified: string;
  path: string;
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

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0a0a0a] via-[#1a1a1a] to-[#0f0f0f]">
      <div className="container mx-auto px-4 py-8 max-w-6xl">
        <div className="batman-card overflow-hidden">
          {/* Header */}
          <div className="bg-gradient-to-r from-[#1a1a1a] via-[#2a2a2a] to-[#1a1a1a] text-white p-8 border-b-2 border-[#ffd700]">
            <div className="flex items-center gap-4 mb-3">
              <div className="w-16 h-16 bg-gradient-to-br from-[#ffd700] to-[#ffb900] rounded-lg flex items-center justify-center shadow-lg shadow-[#ffd700]/50">
                <Home size={32} className="text-black" />
              </div>
              <div>
                <h1 className="text-4xl font-black tracking-wider mb-1 bg-gradient-to-r from-[#ffd700] to-[#ffb900] bg-clip-text text-transparent">
                  GABRIEL
                </h1>
                <p className="text-gray-400 text-sm">Your Digital Storage Vault</p>
              </div>
            </div>
            <div className="flex items-center gap-2 mt-4 px-2">
              <div className="w-2 h-2 bg-[#ffd700] rounded-full animate-pulse"></div>
              <p className="text-[#ffd700] text-sm font-semibold">Secure • Fast • Organized</p>
            </div>
          </div>

          {/* Upload Progress Indicator */}
          {uploading && (
            <div className="bg-gradient-to-r from-[#1a1a1a] to-[#2a2a2a] border-b-2 border-[#ffd700]/30 p-6">
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="relative">
                      <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-t-2 border-[#ffd700]"></div>
                      <div className="absolute inset-0 animate-ping rounded-full bg-[#ffd700]/20"></div>
                    </div>
                    <span className="text-[#ffd700] font-semibold">{uploadProgress}</span>
                  </div>
                  <span className="text-[#ffd700] font-bold text-xl">{uploadPercent}%</span>
                </div>
                {/* Progress Bar */}
                <div className="batman-progress h-4">
                  <div 
                    className="batman-progress-bar"
                    style={{ width: `${uploadPercent}%`, backgroundSize: '200% 100%' }}
                  ></div>
                </div>
                <p className="text-xs text-gray-400 text-right flex items-center justify-end gap-2">
                  <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse"></span>
                  System operational - navigate freely
                </p>
              </div>
            </div>
          )}

          {/* Toolbar */}
          <div className="border-b border-[#333333] bg-[#1a1a1a] p-5">
            <div className="flex flex-wrap gap-3 items-center">
              <button
                onClick={navigateHome}
                className="batman-button"
                title="Home"
                disabled={uploading}
              >
                <Home size={18} className="inline mr-2" />
                <span className="hidden sm:inline">HOME</span>
              </button>
              
              {currentPath && (
                <button
                  onClick={navigateBack}
                  className="batman-button-secondary disabled:opacity-30 disabled:cursor-not-allowed"
                  disabled={uploading}
                >
                  <ArrowLeft size={18} className="inline mr-2" />
                  <span className="hidden sm:inline">BACK</span>
                </button>
              )}

              <label className={`batman-button ${uploading ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}>
                <Upload size={18} className="inline mr-2" />
                <span className="hidden sm:inline">UPLOAD FILE</span>
                <input
                  type="file"
                  onChange={handleFileInputChange}
                  className="hidden"
                  disabled={uploading}
                />
              </label>

              <label className={`batman-button-secondary ${uploading ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}>
                <Folder size={18} className="inline mr-2" />
                <span className="hidden sm:inline">UPLOAD FOLDER</span>
                <input
                  type="file"
                  onChange={handleFolderInputChange}
                  className="hidden"
                  {...({ webkitdirectory: '', directory: '' } as any)}
                  multiple
                  disabled={uploading}
                />
              </label>

              <button
                onClick={() => setShowNewFolderInput(!showNewFolderInput)}
                className="batman-button-secondary disabled:opacity-30 disabled:cursor-not-allowed"
                disabled={uploading}
              >
                <FolderPlus size={18} className="inline mr-2" />
                <span className="hidden sm:inline">NEW FOLDER</span>
              </button>
            </div>

            {/* New Folder Input */}
            {showNewFolderInput && (
              <div className="mt-4 flex gap-2">
                <input
                  type="text"
                  value={newFolderName}
                  onChange={(e) => setNewFolderName(e.target.value)}
                  placeholder="Enter folder name..."
                  className="batman-input flex-1"
                  onKeyPress={(e) => e.key === 'Enter' && handleCreateFolder()}
                />
                <button
                  onClick={handleCreateFolder}
                  className="batman-button"
                >
                  CREATE
                </button>
                <button
                  onClick={() => {
                    setShowNewFolderInput(false);
                    setNewFolderName('');
                  }}
                  className="batman-button-secondary"
                >
                  CANCEL
                </button>
              </div>
            )}
          </div>

          {/* Breadcrumb */}
          <div className="bg-[#0f0f0f] border-b border-[#333333] p-4">
            <div className="flex items-center gap-2 text-sm">
              <div className="w-8 h-8 bg-[#ffd700]/10 rounded-lg flex items-center justify-center">
                <Home size={14} className="text-[#ffd700]" />
              </div>
              <button 
                onClick={navigateHome}
                className="breadcrumb font-semibold"
              >
                uploads
              </button>
              {pathSegments.map((segment, index) => (
                <span key={index} className="flex items-center gap-2">
                  <span className="text-[#ffd700]">/</span>
                  <button
                    onClick={() => navigateToFolder(pathSegments.slice(0, index + 1).join('/'))}
                    className="breadcrumb font-semibold"
                  >
                    {segment}
                  </button>
                </span>
              ))}
            </div>
          </div>

          {/* Drop Zone */}
          <div
            onDragEnter={handleDrag}
            onDragLeave={handleDrag}
            onDragOver={handleDrag}
            onDrop={handleDrop}
            className={`relative ${dragActive && !uploading ? 'bg-[#ffd700]/5' : ''}`}
          >
            {dragActive && !uploading && (
              <div className="absolute inset-0 bg-gradient-to-br from-[#ffd700]/20 to-[#ffb900]/20 flex items-center justify-center z-10 border-4 border-dashed border-[#ffd700] m-4 rounded-lg backdrop-blur-sm">
                <div className="text-center p-8 bg-[#1a1a1a]/90 rounded-xl border border-[#ffd700]/50 shadow-2xl shadow-[#ffd700]/30">
                  <Upload size={64} className="mx-auto text-[#ffd700] mb-4 animate-pulse" />
                  <p className="text-2xl font-bold text-[#ffd700] mb-2">RELEASE TO UPLOAD</p>
                  <p className="text-gray-400">Files will be secured instantly</p>
                </div>
              </div>
            )}

            {uploading && (
              <div className="absolute inset-0 bg-[#0a0a0a]/95 flex items-center justify-center z-20 m-4 rounded-lg backdrop-blur-lg">
                <div className="text-center bg-gradient-to-br from-[#1a1a1a] to-[#0f0f0f] p-10 rounded-2xl shadow-2xl max-w-md w-full mx-4 border-2 border-[#ffd700]/30">
                  <div className="relative mb-6">
                    <div className="animate-spin rounded-full h-20 w-20 border-b-4 border-t-4 border-[#ffd700] mx-auto"></div>
                    <div className="absolute inset-0 animate-ping rounded-full bg-[#ffd700]/20 mx-auto" style={{width: '80px', height: '80px', margin: 'auto'}}></div>
                  </div>
                  <p className="text-xl font-bold text-white mb-4">{uploadProgress}</p>
                  <div className="batman-progress h-4 mb-4">
                    <div 
                      className="batman-progress-bar"
                      style={{ width: `${uploadPercent}%`, backgroundSize: '200% 100%' }}
                    ></div>
                  </div>
                  <p className="text-3xl font-black bg-gradient-to-r from-[#ffd700] to-[#ffb900] bg-clip-text text-transparent mb-2">{uploadPercent}%</p>
                  <p className="text-sm text-gray-400">Processing secure transfer...</p>
                </div>
              </div>
            )}

            {/* File List */}
            <div className="p-6 min-h-[400px]">
              {loading ? (
                <div className="text-center py-20">
                  <div className="relative inline-block">
                    <div className="animate-spin rounded-full h-16 w-16 border-b-4 border-t-4 border-[#ffd700]"></div>
                    <div className="absolute inset-0 animate-ping rounded-full bg-[#ffd700]/20"></div>
                  </div>
                  <p className="mt-6 text-[#ffd700] font-semibold text-lg">LOADING FILES...</p>
                  <p className="text-gray-500 text-sm mt-2">Accessing vault...</p>
                </div>
              ) : files.length === 0 ? (
                <div className="text-center py-20">
                  <div className="w-24 h-24 bg-[#ffd700]/10 rounded-2xl flex items-center justify-center mx-auto mb-6 border-2 border-[#ffd700]/30">
                    <Folder size={48} className="text-[#ffd700]" />
                  </div>
                  <p className="text-xl font-bold text-gray-300 mb-2">VAULT IS EMPTY</p>
                  <p className="text-gray-500">Upload files or create folders to begin</p>
                </div>
              ) : (
                <div className="grid gap-3">
                  {files.map((file, index) => (
                    <div
                      key={index}
                      className="file-item"
                    >
                      <div className="flex items-center justify-between">
                        <div 
                          className="flex items-center gap-4 flex-1 cursor-pointer"
                          onClick={() => file.isDirectory ? navigateToFolder(file.path) : handleImagePreview(file)}
                        >
                          <div className={`w-12 h-12 rounded-lg flex items-center justify-center overflow-hidden ${file.isDirectory ? 'bg-[#ffd700]/10' : 'bg-[#333333]'}`}>
                            {file.isDirectory ? (
                              // Batarang/Batman icon for folders
                              <svg viewBox="0 0 100 50" className="w-8 h-8 text-[#ffd700]" fill="currentColor">
                                <path d="M50,5 L65,15 L80,10 L75,25 L90,30 L80,35 L85,45 L70,42 L60,48 L50,40 L40,48 L30,42 L15,45 L20,35 L10,30 L25,25 L20,10 L35,15 Z" />
                                <ellipse cx="50" cy="25" rx="8" ry="10" fill="#0a0a0a" opacity="0.5"/>
                              </svg>
                            ) : isImageFile(file.name) ? (
                              // Show image thumbnail for image files
                              <img 
                                src={`/api/download?path=${encodeURIComponent(file.path)}`}
                                alt={file.name}
                                className="w-full h-full object-cover"
                                loading="lazy"
                              />
                            ) : (
                              getFileIcon(file.name)
                            )}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <p className="font-semibold text-gray-100 truncate text-lg">{file.name}</p>
                              {!file.isDirectory && isImageFile(file.name) && (
                                <span title="Click to preview">
                                  <Eye size={16} className="text-[#ffd700] opacity-70" />
                                </span>
                              )}
                            </div>
                            <p className="text-sm text-gray-500 flex items-center gap-2">
                              <span>{file.isDirectory ? 'FOLDER' : formatFileSize(file.size)}</span>
                              <span className="text-[#ffd700]">•</span>
                              <span>{formatDate(file.modified)}</span>
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2 ml-4">
                          {!file.isDirectory && (
                            <button
                              onClick={() => handleDownload(file.path, file.name)}
                              className="p-3 text-[#ffd700] hover:bg-[#ffd700]/10 rounded-lg transition-all hover:scale-110 border border-[#ffd700]/0 hover:border-[#ffd700]/50"
                              title="Download"
                            >
                              <Download size={20} />
                            </button>
                          )}
                          <button
                            onClick={() => handleDelete(file.path, file.name)}
                            className="p-3 text-red-500 hover:bg-red-500/10 rounded-lg transition-all hover:scale-110 border border-red-500/0 hover:border-red-500/50"
                            title="Delete"
                          >
                            <Trash2 size={20} />
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-6 text-center">
          <p className="text-gray-600 text-sm flex items-center justify-center gap-2">
            <span className="w-2 h-2 bg-[#ffd700] rounded-full animate-pulse"></span>
            Powered by <span className="font-bold text-[#ffd700]">GABRIEL</span> - Your Secure Storage Solution
          </p>
        </div>
      </div>

      {/* Image Preview Modal */}
      {previewImage && (
        <div 
          className="fixed inset-0 bg-black/90 backdrop-blur-sm z-50 flex items-center justify-center p-4"
          onClick={() => setPreviewImage(null)}
        >
          <div className="relative max-w-7xl max-h-[90vh] w-full h-full flex items-center justify-center">
            <button
              onClick={() => setPreviewImage(null)}
              className="absolute top-4 right-4 p-3 bg-[#ffd700] text-black rounded-lg hover:bg-[#ffb900] transition-all z-10 font-bold"
            >
              ✕ CLOSE
            </button>
            <img 
              src={previewImage} 
              alt="Preview" 
              className="max-w-full max-h-full object-contain rounded-lg shadow-2xl shadow-[#ffd700]/20"
              onClick={(e) => e.stopPropagation()}
            />
          </div>
        </div>
      )}
    </div>
  );
}

