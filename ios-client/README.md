# iOS Client for Gabriel (SwiftUI)

This folder contains a small SwiftUI example client that talks to the existing Gabriel Next.js server API. The app is a native iPhone client that lists files, uploads files/folders, downloads files, and previews images using the same REST endpoints in the server.

High-level instructions
- Make sure the Next.js server is running on your machine (e.g. `http://192.168.1.100:3000` or `http://localhost:3000` if using simulators). The app needs a reachable server address.
- Open the Swift files in Xcode and create a new iOS project (or copy the code into your existing project). These files are examples — you'll want to integrate them into a full Xcode project.

Configuration
- Set the `SERVER_BASE_URL` in `FileManagerClient.swift` to your server's base URL (including port). For example:
  let SERVER_BASE_URL = "http://192.168.1.100:3000"

Notes
- CORS: the repository's `next.config.ts` has been updated to allow CORS for `/api` during development so the mobile app can talk to it. In production, restrict origins.
- The example uses URLSession multipart form-data uploads. It demonstrates progress and basic error handling.
- On-device file/folder uploads (preserving folder structure) require picking files with directory info; iOS's UIDocumentPicker can provide file URLs. See the example usage in `ContentView.swift`.

Security & Production
- This example is for development and demo use. Add authentication, TLS, and server-side rate limiting before exposing any real data.

Files
- `FileManagerClient.swift` — network client and upload/download helpers
- `Models.swift` — data models used by the client
- `ContentView.swift` — sample SwiftUI view demonstrating listing, uploading and downloading
