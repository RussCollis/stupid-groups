//
//  AppDelegate.swift
//  Stupid Groups
//
//  Created by Michael Levenick on 1/21/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//
//  Updated by Russell Collis to modernize to native SwiftUI with
//  accessible text boxes, colors, and design.
//

import SwiftUI
import AppKit

@main
struct StupidGroupsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authSession = AuthSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authSession)
                .frame(minWidth: 700, idealWidth: 840, minHeight: 600, idealHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Stupid Groups") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "Stupid Groups",
                            NSApplication.AboutPanelOptionKey.version: "1.2"
                        ]
                    )
                }
            }

            CommandGroup(after: .appSettings) {
                Button("Clear Stored Credentials") {
                    authSession.clearStoredCredentials()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                if authSession.isAuthenticated {
                    Button("Disconnect from Jamf Pro") {
                        authSession.logOut()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Application did finish launching
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Handled via AuthSession notification observer
    }

    // Causes app to be quit properly after last window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
