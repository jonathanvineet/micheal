import SwiftUI
import LocalAuthentication

@main
struct GabrielApp: App {
    @StateObject private var authManager = AuthenticationManager()
    
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
        
        let reason = "Unlock Gabriel to access your files"
        
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
        let reason = "Unlock Gabriel to access your files"
        
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
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text("Gabriel")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Locked")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                
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
                }
                .padding(.top, 50)
            }
        }
    }
}
