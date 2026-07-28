import Foundation

enum AppConfig {
    // Swap to the local Next.js dev server (see sparklet/AGENTS.md — runs on
    // PORT=3001 to avoid clashing with other :3000 servers) while iterating
    // against a local backend.
    static let apiBaseURL = URL(string: "https://sparkletapp.com")!

    // Must match project.yml's CFBundleURLTypes scheme and the backend's
    // native-login callback (see Auth/LoginView.swift).
    static let authCallbackScheme = "sparklet"
}
