//
//  loginWindow.swift
//  Stupid Groups
//
//  Created by Michael Levenick on 1/21/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//
//  Updated by Russell Collis to modernize to native SwiftUI with
//  accessible text boxes, colors, and design.
//

import SwiftUI
import Foundation

// MARK: - AuthSession Observable Object

public class AuthSession: ObservableObject {
    @Published public var baseURL: String = ""
    @Published public var serverURL: String = ""
    @Published public var bearerToken: String = ""
    @Published public var tokenExpiry: Date? = nil
    @Published public var basicCredentials: String = "" // Kept ONLY in-memory for silent token refresh
    @Published public var isAuthenticated: Bool = false
    @Published public var isAuthenticating: Bool = false
    @Published public var authErrorMessage: String? = nil

    // Form inputs
    @Published public var inputURL: String = ""
    @Published public var inputUsername: String = ""
    @Published public var inputPassword: String = ""
    @Published public var rememberMe: Bool = true

    private let defaults = UserDefaults.standard
    private let punctuation = CharacterSet(charactersIn: ".:/")

    public init() {
        loadSavedCredentials()
        setupTerminationObserver()
    }

    public func loadSavedCredentials() {
        if let savedUser = defaults.string(forKey: "UserName") {
            inputUsername = savedUser
        }
        if let savedURL = defaults.string(forKey: "InstanceURL") {
            inputURL = savedURL
        }
        if defaults.object(forKey: "Remember") != nil {
            rememberMe = defaults.bool(forKey: "Remember")
        }
    }

    public func clearStoredCredentials() {
        inputUsername = ""
        inputURL = ""
        inputPassword = ""
        defaults.removeObject(forKey: "UserName")
        defaults.removeObject(forKey: "InstanceURL")
        defaults.set(false, forKey: "Remember")
        defaults.synchronize()
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
    }

    public func logOut() {
        if !bearerToken.isEmpty && !baseURL.isEmpty {
            let invalidateURL = prepareData().createInvalidateURL(baseURL: baseURL)
            API().invalidateToken(token: bearerToken, invalidateURL: invalidateURL)
        }
        bearerToken = ""
        tokenExpiry = nil
        basicCredentials = ""
        isAuthenticated = false
        inputPassword = ""
        authErrorMessage = nil
    }

    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self = self, !self.bearerToken.isEmpty, !self.baseURL.isEmpty else { return }
            let invalidateURL = prepareData().createInvalidateURL(baseURL: self.baseURL)
            API().invalidateToken(token: self.bearerToken, invalidateURL: invalidateURL)
        }
    }

    public func ensureValidToken() {
        guard let expiry = tokenExpiry else { return }
        let remaining = expiry.timeIntervalSinceNow

        if remaining < 60 && !basicCredentials.isEmpty && !baseURL.isEmpty {
            NSLog("[AUTH  ]: Bearer Token expiring soon (\(Int(remaining))s remaining) - refreshing...")
            let tokenURL = prepareData().createTokenURL(baseURL: baseURL)
            if let refreshed = API().getBearerToken(basicCredentials: basicCredentials, tokenURL: tokenURL) {
                DispatchQueue.main.async {
                    self.bearerToken = refreshed.token
                    self.tokenExpiry = refreshed.expires
                }
                NSLog("[AUTH  ]: Bearer Token refreshed successfully.")
            } else {
                NSLog("[ERROR ]: Failed to refresh Bearer Token. Subsequent calls may fail with 401.")
            }
        }
    }

    public func authenticate() {
        let cleanedURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUser = inputUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPass = inputPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedURL.isEmpty else {
            authErrorMessage = "Please enter your Jamf Pro server URL or Jamf Cloud instance name."
            return
        }
        guard !cleanedUser.isEmpty else {
            authErrorMessage = "Please enter an administrator username."
            return
        }
        guard !cleanedPass.isEmpty else {
            authErrorMessage = "Please enter your password."
            return
        }

        authErrorMessage = nil
        isAuthenticating = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var processedURL = cleanedURL
            if processedURL.hasSuffix("/") {
                processedURL.removeLast()
            }

            let resolvedBaseURL: String
            if processedURL.rangeOfCharacter(from: self.punctuation) == nil {
                resolvedBaseURL = "https://\(processedURL).jamfcloud.com/"
            } else {
                if !processedURL.lowercased().hasPrefix("http://") && !processedURL.lowercased().hasPrefix("https://") {
                    processedURL = "https://\(processedURL)"
                }
                resolvedBaseURL = "\(processedURL)/"
            }
            let resolvedServerURL = "\(resolvedBaseURL)JSSResource/"

            let concat = "\(cleanedUser):\(cleanedPass)"
            guard let utf8 = concat.data(using: .utf8) else {
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    self.authErrorMessage = "Failed to encode credentials."
                }
                return
            }
            let encodedCreds = utf8.base64EncodedString()

            let tokenURL = prepareData().createTokenURL(baseURL: resolvedBaseURL)
            guard let tokenResult = API().getBearerToken(basicCredentials: encodedCreds, tokenURL: tokenURL) else {
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    self.authErrorMessage = "Unable to obtain Bearer Token from \(resolvedBaseURL)api/v1/auth/token.\nPlease check your username, password, and URL."
                }
                return
            }

            // Use the new API endpoint to verify permissions (e.g., /api/v1/groups)
            let groupsAPIURL = URL(string: "\(resolvedBaseURL)api/v1/groups")!

            let authResponse = API().getWithBearerToken(tokenResult.token, url: groupsAPIURL)

            DispatchQueue.main.async {
                self.isAuthenticating = false

                if authResponse.isSuccess {
                    self.baseURL = resolvedBaseURL
                    self.serverURL = resolvedServerURL
                    self.bearerToken = tokenResult.token
                    self.tokenExpiry = tokenResult.expires
                    self.basicCredentials = encodedCreds
                    self.isAuthenticated = true
                    self.authErrorMessage = nil

                    if self.rememberMe {
                        self.defaults.set(cleanedUser, forKey: "UserName")
                        self.defaults.set(cleanedURL, forKey: "InstanceURL")
                        self.defaults.set(true, forKey: "Remember")
                    } else {
                        self.defaults.removeObject(forKey: "UserName")
                        self.defaults.removeObject(forKey: "InstanceURL")
                        self.defaults.set(false, forKey: "Remember")
                    }
                    self.defaults.synchronize()
                } else {
                    if authResponse.errorDescription.contains("SSL") {
                        self.authErrorMessage = "SSL Connection Error: \(authResponse.errorDescription)\nIf using a self-signed certificate, please trust it in Keychain Access."
                    } else if authResponse.statusCode == 403 {
                        self.authErrorMessage = "Permission Denied: Your Jamf Pro API role does not have access to smart/static groups or searches via the API.\nPlease contact your Jamf administrator to update your API role permissions."
                    } else if authResponse.statusCode == 401 {
                        self.authErrorMessage = "Unauthorized: Invalid credentials or insufficient API permissions.\nPlease verify your username, password, and API role permissions."
                    } else {
                        self.authErrorMessage = "API Access Error: \(authResponse.errorDescription)\nPlease ensure your credentials have the necessary Jamf Pro API role permissions."
                    }
                }
            }
        }
    }
}

// MARK: - Accessible Text Box View Component

public struct AccessibleInputBox: View {
    let title: String
    let systemImage: String
    let placeholder: String
    let hint: String?
    @Binding var text: String
    var isSecure: Bool = false
    @State private var showPassword: Bool = false
    @FocusState private var isFocused: Bool

    public init(
        title: String,
        systemImage: String,
        placeholder: String,
        hint: String? = nil,
        text: Binding<String>,
        isSecure: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.placeholder = placeholder
        self.hint = hint
        self._text = text
        self.isSecure = isSecure
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, design: .default).weight(.medium))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isFocused ? .accentColor : .secondary)
                    .frame(width: 22)

                if isSecure && !showPassword {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .font(.system(.body, design: .default))
                        .accessibilityLabel(title)
                        .accessibilityHint(hint ?? placeholder)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .font(.system(.body, design: .default))
                        .accessibilityLabel(title)
                        .accessibilityHint(hint ?? placeholder)
                }

                if isSecure {
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    .help(showPassword ? "Hide password" : "Show password")
                } else if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear text")
                    .help("Clear text")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isFocused ? 1.5 : 1)
            )

            if let hint = hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
        }
    }
}

// MARK: - Modern Accessible Login View

public struct LoginView: View {
    @EnvironmentObject var authSession: AuthSession

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header & Branding
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.85), Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)

                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 10)

                    Text("Stupid Groups")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(.primary)

                    Text("Make your Jamf Pro smart groups less smart.")
                        .font(.system(.subheadline, design: .default))
                        .foregroundColor(.secondary)
                }

                // Error Banner
                if let error = authSession.authErrorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.red)

                        Text(error)
                            .font(.system(.callout, design: .default))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Button(action: { authSession.authErrorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss error")
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Error: \(error)")
                }

                // Input Card
                VStack(spacing: 16) {
                    AccessibleInputBox(
                        title: "Jamf Pro Server",
                        systemImage: "server.rack",
                        placeholder: "e.g. your-instance or https://jss.example.com",
                        hint: "Enter your Jamf Cloud instance name or full on-prem URL.",
                        text: $authSession.inputURL
                    )

                    AccessibleInputBox(
                        title: "Username",
                        systemImage: "person.fill",
                        placeholder: "Administrator Username",
                        text: $authSession.inputUsername
                    )

                    AccessibleInputBox(
                        title: "Password",
                        systemImage: "key.fill",
                        placeholder: "Password",
                        text: $authSession.inputPassword,
                        isSecure: true
                    )
                    
                    // Updated Permissions Info Box
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Important:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("API login requires: Jamf Pro API role with access to smart/static groups and searches via the new API.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("Contact your Jamf admin to ensure your role has these permissions.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                    Divider()
                        .padding(.vertical, 4)

                    // Options
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $authSession.rememberMe) {
                            Text("Remember server and username")
                                .font(.subheadline)
                        }
                        .toggleStyle(.checkbox)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

                // Actions
                VStack(spacing: 12) {
                    Button(action: { authSession.authenticate() }) {
                        HStack(spacing: 8) {
                            if authSession.isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(authSession.isAuthenticating ? "Connecting..." : "Connect to Jamf Pro")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(authSession.isAuthenticating)
                    .keyboardShortcut(.defaultAction)

                    HStack {
                        Button("Clear Stored Credentials") {
                            authSession.clearStoredCredentials()
                        }
                        .buttonStyle(.link)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                        Spacer()

                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
        }
        .frame(minWidth: 440, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// Extend API to include getWithBearerToken method for new API endpoint verification

extension API {
    /// Performs a GET request with a Bearer token to verify permissions for the new API endpoint.
    func getWithBearerToken(_ token: String, url: URL) -> (isSuccess: Bool, statusCode: Int, errorDescription: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)

        var responseCode: Int = 0
        var responseErrorDescription = ""
        var success = false

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                responseErrorDescription = error.localizedDescription
            } else if let httpResponse = response as? HTTPURLResponse {
                responseCode = httpResponse.statusCode
                if (200...299).contains(responseCode) {
                    success = true
                } else {
                    responseErrorDescription = HTTPURLResponse.localizedString(forStatusCode: responseCode)
                }
            } else {
                responseErrorDescription = "Unknown error"
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return (success, responseCode, responseErrorDescription)
    }
}
