# File Manager Application

A modern Next.js file manager application that allows you to upload, organize, and manage files and folders locally.

## Features

### 📁 File & Folder Operations
- **Upload Files**: Click "Upload File" button or drag & drop individual files
- **Upload Folders**: Click "Upload Folder" button to upload entire directories with their structure preserved
- **Create Folders**: Create new folders with custom names
- **Navigate Folders**: Browse through your directory structure with breadcrumb navigation
- **Download Files**: Download any file with a single click
- **Delete Files/Folders**: Remove files or entire folders (including all contents)
- **Automatic Compression**: Files/folders larger than 100MB are automatically compressed to save space
- **Progress Tracking**: Real-time upload progress bar with percentage

### 🎨 User Interface
- Modern, responsive design with Tailwind CSS
- Drag & drop support for both files and folders
- Visual feedback with icons and hover effects
- File size and modification date display
- Loading states and error handling
- Real-time progress bar during uploads
- Upload percentage indicator

### 💾 Local Storage
- All files stored in the `/uploads` directory
- Maintains folder structure when uploading directories
- Secure path validation to prevent directory traversal
- Smart compression for large files (>100MB) to save disk space
- Automatic decompression when downloading compressed files

## Getting Started

### Installation
```bash
npm install
```

### Development
```bash
npm run dev
```

The application will be available at `http://localhost:3000`

# Micheal — Local File Manager + Printer Dashboard

A full-stack project combining a Next.js file manager backend with an iOS SwiftUI client that controls a Marlin-based 3D printer and browses cloud/local files. This README describes how to run and develop the server, the iOS app, and how the APIs work.

"Micheal — where files meet filament."

Catchphrase: "Push bytes, pull prints — make things that matter."

## Quick Overview
- Server: Next.js API routes located under `app/api/` serve file storage, printer control, thumbnails and streaming endpoints.
- iOS app: `ios-client/MichealApp` — SwiftUI app that displays the printer dashboard, SD browser, cloud storage browser, and basic TODO list integration.
- Uploads: Local uploads directory served by the Next.js server at `/uploads` (server resolves path relative to project root).

---

## Table of Contents
- Features
- Repo layout
- Getting started (server)
- Running the iOS app
- API reference
- Troubleshooting & notes
- Development tips
- License & credits

---

## Features
- File manager: list, upload, download, delete files & folders; streaming for large files; thumbnail generation.
- Printer control: temperature readout, preheat presets, motion commands, SD card listing, print control (start/pause/stop) and print progress.
- iOS client: UnifiedPrinterCard (status + controls + SD browser), FileManagerView (cloud storage browser), lazy polling, thumbnail previews.
- Robust server serial queue with flushing and delays to avoid Marlin desynchronization.

---

## Repo layout (important folders)
- `app/` — Next.js app routes and server code (APIs live in `app/api/*`).
	- `app/api/files/route.ts` — file listing, download, upload, delete handlers.
	- `app/api/printer/*` — serial proxy, status, SD operations, motion/temperature endpoints.
	- `app/api/thumbnail` — thumbnail generation
- `ios-client/MichealApp/` — SwiftUI iOS client app (ContentView.swift contains the dashboard + FileManagerView + PrinterClient singleton).
- `lib/` — shared Node utilities (imageIndexer, compression helpers).
- `public/` — static assets and upload-worker script.

---

## Getting started — Server (development)
Prerequisites:
- Node 18+ / npm
- (On server machine) Access to serial device (e.g. `/dev/ttyUSB0`) for printer control.

Run locally:

```bash
# install
npm install

# run development server
npm run dev

# open http://localhost:3000
```

Notes:
- The server resolves the uploads directory automatically (searches upward from cwd). Logs include a line like `[files] using uploads dir: /path/to/uploads` on startup.
- If exposing the server externally, use a secure tunneling solution (ngrok / Cloud) and secure the endpoint.

---

## Running the iOS app (development)
Prereqs:
- Xcode (recommended latest stable). Deployment targets in the app support iOS 15+ for iPad and iOS 16+ features are gated by availability checks.
- Make sure the `SERVER_BASE_URL` in `ios-client/MichealApp/FileManagerClient.swift` points to your running Next.js server (use local IP accessible from device or a tunnel URL).

Steps:

1. Open `ios-client/Micheal.xcodeproj` in Xcode.
2. Select `MichealApp` target and a device or simulator (iPhone with iOS 16/17+, iPad on iOS 15+ supported).
3. Build & run.

Developer tips:
- For physical device debugging, ensure the device can reach the server IP (swap `SERVER_BASE_URL` to the machine IP or use ngrok/Cloudflare tunnel).
- The app disables aggressive printer polling while browsing cloud storage to avoid overloading the server.

---

## API Reference (high level)

Server exposes these key endpoints (see `app/api/*`):

- `GET /api/files?path=<path>` — list files in `uploads/<path>`; returns JSON `{ files: [{name,isDirectory,size,modified,path}], currentPath, count }` or streams file bytes when `path` points to a file.
- `POST /api/files` — multipart upload handler. Accepts `path` field and files. Server may auto-compress large uploads.
- `DELETE /api/files` — delete file or folder (server validates path stays within uploads dir).

- `GET /api/printer/status` — returns parsed temperatures and printer state (hotendTemp, hotendTarget, bedTemp, bedTarget, isPrinting, filename, progress bytes).
- `GET /api/printer/sd?action=list` — list files on SD (proxied via serial M20). `action=progress` returns print progress M27.
- `POST /api/printer/motion` — send homing or move commands to the printer.
- `POST /api/printer/serial` — low-level serial proxy (internal). Implemented with a command queue, port flush, inter-command delay.

Also:
- `GET /api/thumbnail?path=...` — returns generated thumbnails for images.
- `GET /api/camera-stream` — server-sent continuous camera stream (if configured).

---

## Troubleshooting — Common issues & fixes

- Temperatures show 0°C / wrong values:
	- Server returns raw M105 reply if parsing failed. Check server logs `🌡️ Parsed temperatures:` to confirm parsing.
	- Ensure serial responses are synchronized; restart server to clear serial queue if responses appear mixed.

- SD listing shows wrong or empty results:
	- Confirm `GET /api/printer/sd?action=list` is being called and server log shows the M20/M27 responses.
	- On iOS, ensure `FileManagerClient.listFiles()` sends a `GET` request (the app now explicitly sets `httpMethod = "GET"`).

- Cloud storage shows upload response instead of listing:
	- This was caused by an old cached POST response. The iOS client was updated to clear caches on `FileManagerView` appear and force fresh GET requests.

- Serial queue corruption (M20 replies attached to M105 etc.):
	- Server-side fix: flush port before commands, add a 50ms inter-command delay, and skip firmware echo lines. If corruption persists, restart server and check serial port health.

---

## Development notes & recommendations

- Keep `ios-client/MichealApp/ContentView.swift` as the single-file SwiftUI host for the printer client and dashboard. The `PrinterClient` singleton is embedded there for now.
- `FileManagerClient.swift` contains the HTTP client used by the iOS app; the `SERVER_BASE_URL` constant must be set for device testing.
- Use `git log` to locate the `printerbackend` commit if you need to restore a known-good state (`git show 24be68b` contains the FileManager client that worked previously).

---

## Tests & Validation

- Server can be validated by curling the endpoints:

```bash
curl "http://localhost:3000/api/files"
curl "http://localhost:3000/api/printer/status"
```

- iOS: Run on simulator or device; open Xcode Console to inspect logs from `FileManagerClient` and `PrinterClient` — useful debug prints are included around file list requests and printer status polling.

---

## Next steps & ideas

- Add authentication for cloud storage endpoints (JWT / API key) if exposing publicly.
- Move `PrinterClient` into its own Swift file and introduce unit/integration tests for the serial proxy.
- Add automated end-to-end tests for uploads and thumbnail generation.

---

## Credits

- Author: Project repository owner.
- Utilities: compression helpers in `lib/compression.ts`, thumbnail generation, streaming resources in `app/api/*`.

---

If anything is unclear or you want this README saved to a different file, tell me and I'll update it. Happy printing!
