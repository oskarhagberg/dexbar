//
//  DexBarApp.swift
//  DexBar
//
//  Created by Oskar Hagberg on 2025-08-21.
//

import SwiftUI

@main
struct DexBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() } // No settings UI
    }
}
