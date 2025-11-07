'use client';

import { useState, useEffect } from 'react';
import { 
  Folder, 
  File, 
  Upload, 
  FolderPlus, 
  ArrowLeft, 
  Trash2, 
  Download,
  Home
} from 'lucide-react';

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
  const [showNewFolderInput, setShowNewFolderInput] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');
  const [dragActive, setDragActive] = useState(false);

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

  const handleFileUpload = async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('path', currentPath);

    try {
      const response = await fetch('/api/files', {
        method: 'POST',
        body: formData,
      });

      const data = await response.json();
      if (data.success) {
        loadFiles();
        alert(`File "${file.name}" uploaded successfully!`);
      } else {
        alert(data.error || 'Upload failed');
      }
    } catch (error) {
      console.error('Error uploading file:', error);
      alert('Failed to upload file');
    }
  };

  const handleFileInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      handleFileUpload(file);
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

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      handleFileUpload(e.dataTransfer.files[0]);
    }
  };

  const pathSegments = currentPath.split('/').filter(Boolean);

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100">
      <div className="container mx-auto px-4 py-8 max-w-6xl">
        <div className="bg-white rounded-2xl shadow-xl overflow-hidden">
          {/* Header */}
          <div className="bg-gradient-to-r from-blue-600 to-blue-700 text-white p-6">
            <h1 className="text-3xl font-bold mb-2">File Manager</h1>
            <p className="text-blue-100">Upload, organize, and manage your files</p>
          </div>

          {/* Toolbar */}
          <div className="border-b bg-gray-50 p-4">
            <div className="flex flex-wrap gap-3 items-center">
              <button
                onClick={navigateHome}
                className="flex items-center gap-2 px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition-colors"
                title="Home"
              >
                <Home size={18} />
                <span className="hidden sm:inline">Home</span>
              </button>
              
              {currentPath && (
                <button
                  onClick={navigateBack}
                  className="flex items-center gap-2 px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition-colors"
                >
                  <ArrowLeft size={18} />
                  <span className="hidden sm:inline">Back</span>
                </button>
              )}

              <label className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 cursor-pointer transition-colors">
                <Upload size={18} />
                <span className="hidden sm:inline">Upload File</span>
                <input
                  type="file"
                  onChange={handleFileInputChange}
                  className="hidden"
                />
              </label>

              <button
                onClick={() => setShowNewFolderInput(!showNewFolderInput)}
                className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
              >
                <FolderPlus size={18} />
                <span className="hidden sm:inline">New Folder</span>
              </button>
            </div>

            {/* New Folder Input */}
            {showNewFolderInput && (
              <div className="mt-4 flex gap-2">
                <input
                  type="text"
                  value={newFolderName}
                  onChange={(e) => setNewFolderName(e.target.value)}
                  placeholder="Folder name"
                  className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                  onKeyPress={(e) => e.key === 'Enter' && handleCreateFolder()}
                />
                <button
                  onClick={handleCreateFolder}
                  className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                >
                  Create
                </button>
                <button
                  onClick={() => {
                    setShowNewFolderInput(false);
                    setNewFolderName('');
                  }}
                  className="px-6 py-2 bg-gray-300 text-gray-700 rounded-lg hover:bg-gray-400 transition-colors"
                >
                  Cancel
                </button>
              </div>
            )}
          </div>

          {/* Breadcrumb */}
          <div className="bg-white border-b p-4">
            <div className="flex items-center gap-2 text-sm text-gray-600">
              <Home size={16} className="text-gray-400" />
              <button 
                onClick={navigateHome}
                className="hover:text-blue-600 font-medium"
              >
                uploads
              </button>
              {pathSegments.map((segment, index) => (
                <span key={index} className="flex items-center gap-2">
                  <span className="text-gray-400">/</span>
                  <button
                    onClick={() => navigateToFolder(pathSegments.slice(0, index + 1).join('/'))}
                    className="hover:text-blue-600 font-medium"
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
            className={`relative ${dragActive ? 'bg-blue-50' : ''}`}
          >
            {dragActive && (
              <div className="absolute inset-0 bg-blue-100 bg-opacity-90 flex items-center justify-center z-10 border-4 border-dashed border-blue-400 m-4 rounded-lg">
                <div className="text-center">
                  <Upload size={48} className="mx-auto text-blue-600 mb-2" />
                  <p className="text-xl font-semibold text-blue-600">Drop file here to upload</p>
                </div>
              </div>
            )}

            {/* File List */}
            <div className="p-6">
              {loading ? (
                <div className="text-center py-12 text-gray-500">
                  <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
                  <p className="mt-4">Loading files...</p>
                </div>
              ) : files.length === 0 ? (
                <div className="text-center py-12 text-gray-500">
                  <Folder size={48} className="mx-auto mb-4 text-gray-300" />
                  <p className="text-lg">This folder is empty</p>
                  <p className="text-sm mt-2">Upload files or create a new folder to get started</p>
                </div>
              ) : (
                <div className="grid gap-2">
                  {files.map((file, index) => (
                    <div
                      key={index}
                      className="flex items-center justify-between p-4 hover:bg-gray-50 rounded-lg border border-gray-200 transition-colors group"
                    >
                      <div 
                        className="flex items-center gap-4 flex-1 cursor-pointer"
                        onClick={() => file.isDirectory && navigateToFolder(file.path)}
                      >
                        {file.isDirectory ? (
                          <Folder size={32} className="text-blue-500 flex-shrink-0" />
                        ) : (
                          <File size={32} className="text-gray-500 flex-shrink-0" />
                        )}
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-gray-900 truncate">{file.name}</p>
                          <p className="text-sm text-gray-500">
                            {file.isDirectory ? 'Folder' : formatFileSize(file.size)} • {formatDate(file.modified)}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 ml-4">
                        {!file.isDirectory && (
                          <button
                            onClick={() => handleDownload(file.path, file.name)}
                            className="p-2 text-blue-600 hover:bg-blue-100 rounded-lg transition-colors"
                            title="Download"
                          >
                            <Download size={18} />
                          </button>
                        )}
                        <button
                          onClick={() => handleDelete(file.path, file.name)}
                          className="p-2 text-red-600 hover:bg-red-100 rounded-lg transition-colors"
                          title="Delete"
                        >
                          <Trash2 size={18} />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

