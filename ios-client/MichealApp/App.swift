import SwiftUI
import LocalAuthentication

@main
struct MichealApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ContentView()
                    .onAppear {
                        authManager.setupBackgroundAuth()
                    }
            } else {
                LockScreen(authManager: authManager)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
    }
    
    // Optimize app lifecycle and resource management
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // App became active - reconnect streams if needed
            print("App active - resuming operations")
        case .inactive:
            // App about to become inactive - prepare for background
            print("App inactive")
        case .background:
            // App in background - reduce resource usage
            print("App background - cleaning up resources")
            // Camera stream will be managed by MJPEGStreamView
        @unknown default:
            break
        }
    }
}

// Authentication Manager
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    private let context = LAContext()
    
    init() {
        // Require auth on app launch
        authenticate()
    }
    
    func setupBackgroundAuth() {
        // Re-authenticate when app comes back from background
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAuthenticated = false
            self?.authenticate()
        }
    }
    
    func authenticate() {
        var error: NSError?
        
        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to passcode if Face ID/Touch ID unavailable
            authenticateWithPasscode()
            return
        }
        
        let reason = "Unlock Micheal to access your files"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                } else {
                    // If biometric fails, try passcode
                    self?.authenticateWithPasscode()
                }
            }
        }
    }
    
    private func authenticateWithPasscode() {
        let reason = "Unlock Micheal to access your files"
        
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                } else {
                    // Keep showing lock screen
                    print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
}

// Lock Screen View
struct LockScreen: View {
    @ObservedObject var authManager: AuthenticationManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var loaderImageName: String {
        // Detect device type
        let idiom = UIDevice.current.userInterfaceIdiom
        
        switch idiom {
        case .phone:
            return "loader"
        case .pad:
            return "loader-ipad"
        default:
            return "loader"
        }
    }
    
    var body: some View {
        ZStack {
            // Device-specific loader background
            if let image = UIImage(named: loaderImageName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                // Fallback gradient if image not found
                LinearGradient(
                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            
            // Dark overlay for better visibility
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                
                Text("Micheal")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                
                Text("Locked")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                
                Button(action: {
                    authManager.authenticate()
                }) {
                    HStack {
                        Image(systemName: "faceid")
                        Text("Unlock with Face ID")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(15)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                }
                .padding(.top, 50)
            }
        }
    }
}
