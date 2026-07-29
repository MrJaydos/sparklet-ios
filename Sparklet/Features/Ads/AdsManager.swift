import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency

// Runs once at app launch (SparkletApp.swift): gathers UMP consent — a
// legal requirement in the EEA/UK, not just politeness, and the reason
// this can't simply call MobileAds.shared.start() directly — then Apple's
// separate App Tracking Transparency prompt (after consent resolves, so
// IDFA-based ad targeting only kicks in once the user's actually had a
// say), then starts the Mobile Ads SDK.
//
// AdSlideView independently re-checks ConsentInformation.shared
// .canRequestAds before ever loading a real ad rather than trusting this
// ran first — belt-and-braces against any launch-sequencing race, and
// GADMobileAds.h's own doc comment on startWithCompletionHandler: notes
// the SDK auto-starts on the first ad request anyway if this is never
// called at all.
//
// All UMP/GoogleMobileAds types below require the main thread per their
// own header comments ("All methods must be called on the main thread") —
// hence @MainActor on the whole type rather than per-call.
@MainActor
enum AdsManager {
    static func start() async {
        let parameters = RequestParameters()
        #if DEBUG
        // "Debug features are always enabled for simulators" per
        // UMPDebugSettings.h — forces the real EEA consent form to render
        // during Simulator/dev testing without registering a test device
        // id. Never compiled into a Release build.
        let debugSettings = DebugSettings()
        debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif

        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { _ in
                continuation.resume()
            }
        }

        if let rootViewController {
            await withCheckedContinuation { continuation in
                ConsentForm.loadAndPresentIfRequired(from: rootViewController) { _ in
                    continuation.resume()
                }
            }
        }

        guard ConsentInformation.shared.canRequestAds else { return }

        if #available(iOS 14, *) {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        await withCheckedContinuation { continuation in
            MobileAds.shared.start { _ in
                continuation.resume()
            }
        }
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
