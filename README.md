# Micheal

Batman's Oracle

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
# Micheal — Local File Manager + Printer Dashboard

"Micheal — where files meet filament."

Push bytes, pull prints — make things that matter.

Overview
--------
Micheal is a full-stack, self-hosted project combining a Next.js file manager backend with a SwiftUI iOS client. The server provides local/cloud file storage, thumbnailing, streaming and a serial proxy to control a Marlin-based 3D printer. The iOS app provides a unified dashboard to monitor and control the printer, browse cloud files, and manage uploads.

This README documents how to run the server, use the iOS app, and understand the key APIs and troubleshooting steps.

Key features
------------
- File management: list, upload, download, delete files and folders under a configurable `uploads/` directory.
- Streaming & thumbnails: serve large files efficiently and generate thumbnails for images.
- Printer integration: serial proxy to Marlin firmware, endpoints for temperatures, motion, SD listing, and print control.
- iOS client: unified printer card (status + controls + SD browser), FileManagerView (cloud storage browser), lazy polling to reduce server load.
- Robustness: server-side serial queue with flushing and inter-command delays to avoid firmware desync.

Repository layout
-----------------
- `app/` — Next.js app routes and server code (`app/api/*`) including `files`, `printer`, `thumbnail`, `camera-stream`.
- `ios-client/MichealApp/` — SwiftUI iOS app; `ContentView.swift` holds the dashboard and embedded `PrinterClient` and `FileManagerClient`.
- `lib/` — Node utilities (compression, indexing, watchers).
- `public/` — static assets and client-side worker scripts.
- `scripts/` — helper scripts (thumbnail generation, setup).

Quickstart — server
-------------------
Requirements:
- Node.js 18+
- npm
- If using printer features, the server host must have access to the serial device (e.g. `/dev/ttyUSB0`).

Install and run:

```bash
npm install
npm run dev
```

The server will start on `http://localhost:3000` by default. On startup, the server logs the uploads directory used, e.g.:

```
[files] using uploads dir: /path/to/project/uploads
```

Notes:
- The server will automatically create the `uploads` folder if missing.
- Large uploads (>100MB) may be compressed automatically for storage efficiency.

Quickstart — iOS app
--------------------
Requirements:
- Xcode (recommended latest stable) — the app targets iOS 15+ with iOS 16+ features gated by availability checks.
- Ensure `ios-client/MichealApp/FileManagerClient.swift` has `SERVER_BASE_URL` pointing to the running server (use a reachable IP from your device or a tunnel URL).

Open `ios-client/Micheal.xcodeproj` in Xcode, select the `MichealApp` target and run on a simulator or device.

Developer tips:
- For testing on a physical device, either connect the device to the same local network as the server machine and use the host IP, or use a tunneling solution (ngrok / cloud tunnel).
- The app clears caches before loading the FileManagerView to avoid stale responses.

API reference (summary)
-----------------------
This is a high-level summary — see `app/api/*` for implementation details.

- `GET /api/files?path=<path>`
	- Returns JSON: `{ files: [{ name, isDirectory, size, modified, path }], currentPath, count }`.
	- If the `path` points to a file, the server streams the file bytes with appropriate `Content-Type`.

- `POST /api/files`
	- Multipart upload endpoint. Accepts `path` field and uploaded files. Large uploads may be compressed.

- `DELETE /api/files`
	- Deletes a file or folder. Server validates paths so operations stay within the uploads directory.

- `GET /api/thumbnail?path=...`
	- Returns generated thumbnails for images.

- `GET /api/printer/status`
	- Returns parsed temperature values and print progress: `hotendTemp`, `hotendTarget`, `bedTemp`, `bedTarget`, `isPrinting`, `filename`, `bytesPrinted`, `totalBytes`.

- `GET /api/printer/sd?action=list` and `action=progress`
	- Proxies M20 and M27 commands over the serial connection.

- `POST /api/printer/motion`
	- Send movement/home commands to the printer.

Troubleshooting & common fixes
------------------------------
1. Temperatures show 0°C or invalid values
	 - Confirm the server `GET /api/printer/status` logs `🌡️ Parsed temperatures:`. If not, the server returned raw firmware output that couldn't be parsed.
	 - Restart the server to clear any serial queue corruption and check the serial device.

2. Cloud storage returns an upload success response when requesting listing
	 - This was previously caused by cached POST responses. The iOS client now clears caches and forces fresh GET requests. Ensure your device receives a fresh `GET /api/files` call (check server logs for `🌐 GET /api/files called`).

3. Serial queue or mixed responses (M20 output mixed with M105 replies)
	 - The server implements a serial command queue, flushes the port before each command, and waits a small delay between commands. If you still see corruption, restart the server and verify the serial device stability.

4. Uploads fail with connection resets
	 - Large uploads may take time; check server logs and network stability. The server uses streaming for large files and can compress uploads if necessary.

Development notes
-----------------
- The iOS app embeds `PrinterClient` and `FileManagerClient` singletons for now. Refactoring them into separate Swift files is recommended for maintainability.
- The server `app/api/printer/serial.ts` contains the serial queue implementation with a 50ms inter-command delay and 4s timeouts.
- Use `git log` to locate historical commits like `printerbackend` if you need to restore earlier working states.

Testing endpoints locally
-------------------------
Use `curl` for quick checks:

```bash
curl "http://localhost:3000/api/files"
curl "http://localhost:3000/api/printer/status"
```

If you get a JSON error response, check the server console for detailed logs.

Contributing
------------
- Follow the code style in the repo.
- For server changes, add tests where appropriate and validate large-file streaming.
- For iOS changes, keep UI availability checks (`#available`) for iOS 16+ features; the app supports iOS 15+.

License & credits
-----------------
- This repository is maintained by the project owner.
- Utilities under `lib/` provide compression and indexing helpers.

Contact / Next steps
--------------------
If you want, I can:
- Add a short README inside `ios-client/` with quick build/run steps.
- Create a `CONTRIBUTING.md` or `CHANGELOG.md`.
- Push these changes to a branch and open a PR.

Happy printing! 👋

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
