#!/bin/bash

# Script to install thumbnail generation dependencies on macOS

echo "🔧 Installing thumbnail generation dependencies..."
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew is not installed. Please install it first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

echo "📦 Installing ImageMagick (for HEIC/HEIF image conversion)..."
brew install imagemagick

echo "📦 Installing poppler-utils (for PDF thumbnails - pdftoppm)..."
brew install poppler

echo "📦 Installing ghostscript (for PDF fallback)..."
brew install ghostscript

echo "📦 Installing LibreOffice (for document thumbnails - DOCX, XLSX, etc.)..."
brew install --cask libreoffice

echo ""
echo "✅ All dependencies installed!"
echo ""
echo "Installed tools:"
echo "  - ffmpeg:      $(which ffmpeg 2>/dev/null || echo 'Not found')"
echo "  - convert:     $(which convert 2>/dev/null || echo 'Not found')"
echo "  - pdftoppm:    $(which pdftoppm 2>/dev/null || echo 'Not found')"
echo "  - gs:          $(which gs 2>/dev/null || echo 'Not found')"
echo "  - libreoffice: $(which libreoffice 2>/dev/null || echo 'Not found')"
echo ""
echo "Your server can now generate thumbnails for:"
echo "  ✅ Images (JPG, PNG, GIF, WEBP, BMP, TIFF)"
echo "  ✅ Apple Images (HEIC, HEIF) - via ImageMagick"
echo "  ✅ Videos (MP4, MOV, AVI, MKV, WEBM, etc.)"
echo "  ✅ PDFs"
echo "  ✅ Documents (DOCX, XLSX, PPTX, etc.)"
