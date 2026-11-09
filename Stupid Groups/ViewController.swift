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
        VStack(spacing: 0) {
            // Top Navigation / Server Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    Text(serverHostString)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

                Spacer()

                Button(action: { authSession.logOut() }) {
                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Disconnect and return to login screen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main Content Area
            HSplitView {
                // Left Panel: Form & Controls
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section: Group Settings
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Target Configuration", systemImage: "gearshape.fill")
                                .font(.headline)
                                .foregroundColor(.primary)

                            // Device Type Picker
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Type of Smart Group")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

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
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

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
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )

                        // Action: Pre-Flight Check Button
                        Button(action: runPreflightCheck) {
                            HStack(spacing: 8) {
                                if isProcessing && !isReadyToConvert {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                Text(isProcessing && !isReadyToConvert ? "Checking Group..." : "Pre-Flight Check")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(groupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)

                        // Ready to Convert Banner & Action
                        if isReadyToConvert {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Group Found & Verified")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("Ready to create new \(conversionType.lowercased()).")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Original Name:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(smartGroupName)
                                        .font(.system(.body, design: .monospaced).weight(.medium))
                                        .foregroundColor(.primary)

                                    Text("New Name:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                    Text(newName)
                                        .font(.system(.body, design: .monospaced).weight(.bold))
                                        .foregroundColor(.accentColor)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle(isOn: $deleteOriginalAfterConversion) {
                                        Text("Delete original smart group after conversion")
                                            .font(.subheadline)
                                    }
                                    .toggleStyle(.checkbox)
                                    .accessibilityHint("When enabled, the original smart group is permanently deleted once the new \(conversionType.lowercased()) is created.")

                                    if deleteOriginalAfterConversion {
                                        Text("The original group is only deleted if the conversion succeeds. Jamf Pro will refuse if it is still used by policies, profiles, or other scoping.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
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
                                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                                .font(.system(size: 16, weight: .bold))
                                        }
                                        Text(isProcessing ? "Converting..." : "Convert Group Now")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.large)
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
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.green.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)

                // Right Panel: Activity Console
                VStack(spacing: 0) {
                    // Console Header Bar
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)

                        Text("Activity Log")
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        Button(action: copyLogsToClipboard) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(logs.isEmpty)
                        .help("Copy activity log to clipboard")

                        Button(action: { logs.removeAll() }) {
                            Label("Clear", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(logs.isEmpty)
                        .help("Clear activity log")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    // Console Log Stream
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(logs) { entry in
                                    LogMessageRow(entry: entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(14)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: logs.count) {
                            if let last = logs.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 340, idealWidth: 440)
            }
        }
        .frame(minWidth: 680, minHeight: 580)
        .onAppear {
            if logs.isEmpty {
                appendLog(type: .header, message: "Welcome to Stupid Groups v1.2!")
                appendLog(type: .info, message: "Enter a Smart Group ID and click Pre-Flight Check to inspect the group before converting.")
            }
        }
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
                .foregroundColor(.blue)
                .frame(width: 16)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 16)
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.red)
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
            return .green
        case .error:
            return .red
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
