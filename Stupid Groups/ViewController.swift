//
//  ViewController.swift
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

// MARK: - Log Entry Models

public enum LogType: Equatable {
    case info
    case success
    case error
    case header
}

public struct LogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date = Date()
    public let type: LogType
    public let message: String
}

// MARK: - Main Content View

public struct ContentView: View {
    @EnvironmentObject var authSession: AuthSession

    public var body: some View {
        Group {
            if authSession.isAuthenticated {
                ConverterView()
            } else {
                LoginView()
            }
        }
    }
}

// MARK: - Converter View

public struct ConverterView: View {
    @EnvironmentObject var authSession: AuthSession

    // Conversion options
    @State private var deviceType: String = "Computer"
    @State private var conversionType: String = "Static Group"
    @State private var prefix: String = "SG Converted - "
    @State private var groupID: String = ""

    // Discovered Smart Group details
    @State private var smartGroupName: String = ""
    @State private var siteID: String = ""
    @State private var smartGroupCriteria: String = ""
    @State private var smartGroupMembership: String = ""
    @State private var newName: String = ""

    // UI state
    @State private var isReadyToConvert: Bool = false
    @State private var isProcessing: Bool = false
    @State private var logs: [LogEntry] = []
    @State private var deleteOriginalAfterConversion: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private let deviceOptions = ["Computer", "Mobile Device", "User"]
    private let conversionOptions = ["Static Group", "Advanced Search"]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SidebarPane(serverHost: serverHostString, onDisconnect: { authSession.logOut() })
                .frame(width: 210)

            VStack(alignment: .leading, spacing: 16) {
                Text("Groups  ›  Convert Smart Group")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                PageHeader(
                    title: "Convert Smart Group",
                    subtitle: "Turn a Jamf Pro smart group into a static group or an advanced search."
                ) {
                    Button(action: { authSession.logOut() }) {
                        Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.panel)
                    .help("Disconnect and return to login screen")
                }

                ChipRow {
                    StatChip(symbol: "checkmark.circle.fill", count: logCount(.success), label: "Succeeded", tint: Theme.green)
                    StatChip(symbol: "xmark.octagon.fill", count: logCount(.error), label: "Errors", tint: Theme.red)
                    StatChip(symbol: "list.bullet", count: logs.count, label: "Log entries", tint: Theme.blue)
                }

                HStack(alignment: .top, spacing: 16) {
                    // Left column: form, pre-flight check and conversion
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            configurationPanel

                            if isReadyToConvert {
                                preflightResultPanel
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)

                    // Right column: activity log
                    activityLogPanel
                        .frame(minWidth: 320, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.content)
        }
        .frame(minWidth: 960, minHeight: 620)
        .onAppear {
            if logs.isEmpty {
                appendLog(type: .header, message: "Welcome to Stupid Groups v\(appVersion)!")
                appendLog(type: .info, message: "Enter a Smart Group ID and click Pre-Flight Check to inspect the group before converting.")
            }
        }
    }

    // MARK: - Panels

    private var configurationPanel: some View {
        Panel("Target Configuration") {
            VStack(alignment: .leading, spacing: 14) {
                // Device Type Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type of Smart Group")
                        .font(.system(size: 13, weight: .medium))

                    Picker("Type of Smart Group", selection: $deviceType) {
                        ForEach(deviceOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: deviceType) { resetConversionState() }
                }

                // Conversion Type Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to convert it to")
                        .font(.system(size: 13, weight: .medium))

                    Picker("What to convert it to", selection: $conversionType) {
                        ForEach(conversionOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: conversionType) { resetConversionState() }
                }

                // Prefix Field
                AccessibleInputBox(
                    title: "Prefix to prepend",
                    systemImage: "tag.fill",
                    placeholder: "e.g. SG Converted - ",
                    hint: "Prepended to the original group name.",
                    text: $prefix
                )
                .onChange(of: prefix) { resetConversionState() }

                // Group ID Field
                AccessibleInputBox(
                    title: "Smart Group ID",
                    systemImage: "number",
                    placeholder: "e.g. 42",
                    hint: "Found in your Jamf Pro group URL: id={ID}",
                    text: $groupID
                )
                .onChange(of: groupID) { resetConversionState() }

                // Pre-Flight Check is the page's primary action until a group is verified
                Button(action: runPreflightCheck) {
                    HStack(spacing: 8) {
                        if isProcessing && !isReadyToConvert {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(isProcessing && !isReadyToConvert ? "Checking Group..." : "Pre-Flight Check")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PanelButtonStyle(prominent: !isReadyToConvert))
                .disabled(groupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            }
            .padding(16)
        }
    }

    private var preflightResultPanel: some View {
        Panel("Pre-Flight Result", accessory: {
            StatusLabel(text: "Verified", symbol: "checkmark.circle.fill", color: Theme.green)
        }) {
            VStack(alignment: .leading, spacing: 0) {
                FieldRows(
                    rows: [
                        ("Original name", smartGroupName),
                        ("New name", newName),
                        ("Convert to", conversionType)
                    ],
                    valueColor: ["New name": Theme.navy],
                    monospaced: ["Original name", "New name"]
                )

                Divider().overlay(Theme.border)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $deleteOriginalAfterConversion) {
                            Text("Delete original smart group after conversion")
                                .font(.system(size: 13))
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityHint("When enabled, the original smart group is permanently deleted once the new \(conversionType.lowercased()) is created.")

                        if deleteOriginalAfterConversion {
                            Label("The original group is only deleted if the conversion succeeds. Jamf Pro will refuse if it is still used by policies, profiles, or other scoping.", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 20)
                        }
                    }

                    Button(action: {
                        if deleteOriginalAfterConversion {
                            showDeleteConfirmation = true
                        } else {
                            runConvertGroup()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isProcessing ? "Converting..." : "Convert Group Now")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.panelPrimary)
                    .disabled(isProcessing)
                    .confirmationDialog(
                        "Delete \"\(smartGroupName)\" after converting?",
                        isPresented: $showDeleteConfirmation
                    ) {
                        Button("Convert and Delete Original", role: .destructive) {
                            runConvertGroup()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The original smart group (ID \(groupID.trimmingCharacters(in: .whitespacesAndNewlines))) will be permanently deleted from Jamf Pro once \"\(newName)\" is created. This cannot be undone.")
                    }
                }
                .padding(16)
            }
        }
    }

    private var activityLogPanel: some View {
        Panel("Activity Log", accessory: {
            Button(action: copyLogsToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.panel)
            .disabled(logs.isEmpty)
            .help("Copy activity log to clipboard")

            Button(action: { logs.removeAll() }) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.panel)
            .disabled(logs.isEmpty)
            .help("Clear activity log")
        }) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(logs) { entry in
                            LogMessageRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: logs.count) {
                    if let last = logs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func logCount(_ type: LogType) -> Int {
        logs.filter { $0.type == type }.count
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2"
    }

    private var serverHostString: String {
        if let host = URL(string: authSession.baseURL)?.host {
            return host
        }
        return authSession.baseURL
    }

    private func resetConversionState() {
        if isReadyToConvert {
            isReadyToConvert = false
            smartGroupName = ""
            siteID = ""
            smartGroupCriteria = ""
            smartGroupMembership = ""
            newName = ""
        }
    }

    private func appendLog(type: LogType, message: String) {
        let entry = LogEntry(type: type, message: message)
        logs.append(entry)
    }

    private func copyLogsToClipboard() {
        let combined = logs.map { "[\($0.timestamp.formatted(date: .omitted, time: .standard))] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
    }

    // MARK: - API Actions

    private func runPreflightCheck() {
        let cleanID = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }

        isProcessing = true
        resetConversionState()

        appendLog(type: .info, message: "Gathering data about \(deviceType.lowercased()) group #\(cleanID)...")

        DispatchQueue.global(qos: .userInitiated).async {
            authSession.ensureValidToken()

            let getURL = prepareData().createGETURL(url: authSession.serverURL, deviceType: deviceType, id: cleanID)
            let getResponse = API().get(getToken: authSession.bearerToken, getURL: getURL)

            DispatchQueue.main.async {
                isProcessing = false

                if getResponse.contains("<name>") {
                    let extractedName = prepareData().parseXML(fullXMLString: getResponse, startTag: "name>", endTag: "</name>")
                    let extractedSite = prepareData().parseXML(fullXMLString: getResponse, startTag: "site>", endTag: "</site>")
                    let extractedCriteria = prepareData().parseXML(fullXMLString: getResponse, startTag: "criteria>", endTag: "</criteria>")

                    let deviceData = prepareData().deviceData(deviceType: deviceType, conversionType: conversionType)
                    let extractedMembership = prepareData().parseXML(
                        fullXMLString: getResponse,
                        startTag: "<\(deviceData[1])>",
                        endTag: "</\(deviceData[1])>"
                    )

                    let computedNewName = "\(prefix) \(extractedName)".replacingOccurrences(of: "  ", with: " ")

                    self.smartGroupName = extractedName
                    self.siteID = extractedSite
                    self.smartGroupCriteria = extractedCriteria
                    self.smartGroupMembership = extractedMembership
                    self.newName = computedNewName
                    self.isReadyToConvert = true

                    appendLog(type: .success, message: "Group Found: \"\(extractedName)\"")
                    appendLog(
                        type: .info,
                        message: "Will convert to \(conversionType) named \"\(computedNewName)\". Click 'Convert Group Now' to proceed."
                    )
                } else {
                    appendLog(
                        type: .error,
                        message: "The data gathered by Stupid Groups does not match any existing \(deviceType.lowercased()) group with ID \(cleanID). Please verify the ID."
                    )
                }
            }
        }
    }

    private func runConvertGroup() {
        guard isReadyToConvert else { return }

        isProcessing = true
        let targetName = newName
        let targetConversion = conversionType
        let originalID = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = smartGroupName
        let shouldDeleteOriginal = deleteOriginalAfterConversion

        appendLog(type: .info, message: "Submitting data to create new \(targetConversion.lowercased()) \"\(targetName)\"...")

        DispatchQueue.global(qos: .userInitiated).async {
            authSession.ensureValidToken()

            let deviceData = prepareData().deviceData(deviceType: deviceType, conversionType: targetConversion)
            let postData = prepareData().xmlToPost(
                newName: targetName,
                siteID: siteID,
                criteria: smartGroupCriteria,
                membership: smartGroupMembership,
                conversionType: targetConversion,
                deviceRoot: deviceData[0],
                devicePlural: deviceData[1],
                deviceSingular: deviceData[2]
            )

            let postURL = prepareData().createPOSTURL(url: authSession.serverURL, endpoint: deviceData[3])
            let postResponse = API().post(postToken: authSession.bearerToken, postURL: postURL, postBody: postData)
            let conversionSucceeded = postResponse.contains("<id>")

            // Only remove the original smart group once the replacement exists
            var deleteResult: (isSuccess: Bool, response: String)? = nil
            if conversionSucceeded && shouldDeleteOriginal {
                authSession.ensureValidToken()
                let deleteURL = prepareData().createDELETEURL(url: authSession.serverURL, deviceType: deviceType, id: originalID)
                deleteResult = API().delete(deleteToken: authSession.bearerToken, deleteURL: deleteURL)
            }

            DispatchQueue.main.async {
                isProcessing = false
                isReadyToConvert = false

                if conversionSucceeded {
                    let newID = prepareData().parseXML(fullXMLString: postResponse, startTag: "id>", endTag: "</id>")
                    appendLog(type: .success, message: "Conversion Successful!")
                    appendLog(
                        type: .info,
                        message: "Created \(targetConversion) \"\(targetName)\" with ID #\(newID)."
                    )

                    if let deleteResult = deleteResult {
                        if deleteResult.isSuccess {
                            appendLog(type: .success, message: "Deleted original smart group \"\(originalName)\" (ID #\(originalID)).")
                        } else {
                            appendLog(
                                type: .error,
                                message: "Could not delete original smart group \"\(originalName)\" (ID #\(originalID)). It may still be in use by policies, profiles, or other scoping. The new \(targetConversion.lowercased()) was created successfully.\n\(deleteResult.response)"
                            )
                        }
                    }
                } else if postResponse.contains("Error: Duplicate name") {
                    appendLog(
                        type: .error,
                        message: "ERROR: A \(targetConversion.lowercased()) named \"\(targetName)\" already exists. Please delete it or change the prefix."
                    )
                } else if postResponse.contains("[FATAL ]:") {
                    appendLog(type: .error, message: "FATAL ERROR: \(postResponse)")
                } else {
                    appendLog(type: .error, message: "ERROR: Unexpected API response:\n\(postResponse)")
                }
            }
        }
    }
}

// MARK: - Sidebar Pane

/// Navy sidebar with the app icon, connection status, navigation and version.
public struct SidebarPane: View {
    var serverHost: String? = nil
    var onDisconnect: (() -> Void)? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                Text(appName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.sidebarText)
            }
            .padding(.top, 8)

            if let serverHost {
                VStack(alignment: .leading, spacing: 6) {
                    sidebarHeading("Server")
                    Label {
                        Text(serverHost)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(light: 0x5BC774, dark: 0x5BC774))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.sidebarText)
                    .help("Connected to \(serverHost)")
                    .accessibilityLabel("Connected to \(serverHost)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    sidebarHeading("Tools")
                    Label("Convert Smart Group", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.sidebarText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sidebarSelected, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityAddTraits(.isSelected)
                }
            } else {
                Text("Make your Jamf Pro smart groups less smart.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.sidebarHeading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let onDisconnect {
                Button(action: onDisconnect) {
                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.sidebarDimText)
                .help("Disconnect and return to login screen")
            }

            Text("Version \(versionString)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.sidebarDimText)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar)
    }

    private func sidebarHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.sidebarHeading)
            .accessibilityAddTraits(.isHeader)
    }

    private var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "Stupid Groups"
    }

    // Reads "Version X (build)" from the app bundle so it stays in sync with build settings.
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Accessible Log Message Row

public struct LogMessageRow: View {
    public let entry: LogEntry

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            badgeView

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(entry.message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityPrefix): \(entry.message)")
    }

    @ViewBuilder
    private var badgeView: some View {
        switch entry.type {
        case .header:
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.blue)
                .frame(width: 16)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.green)
                .frame(width: 16)
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.red)
                .frame(width: 16)
        case .info:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)
        }
    }

    private var textColor: Color {
        switch entry.type {
        case .header:
            return .primary
        case .success:
            return Theme.green
        case .error:
            return Theme.red
        case .info:
            return .primary
        }
    }

    private var accessibilityPrefix: String {
        switch entry.type {
        case .header: return "Notice"
        case .success: return "Success"
        case .error: return "Error"
        case .info: return "Information"
        }
    }
}
