//
//  PromptorApp.swift
//  Promptor
//
//  Created by Edrick Da Corte Henriquez on 5/1/25.
//

import SwiftUI

@main
struct PromptorApp: App {
    init() {
        // Disable automatic Metal usage if possible
        if let _ = UserDefaults.standard.object(forKey: "NSUseMetalRenderer") {
            // Setting already exists, don't override
        } else {
            UserDefaults.standard.set(false, forKey: "NSUseMetalRenderer")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(FileAggregator())
        }
    }
}
