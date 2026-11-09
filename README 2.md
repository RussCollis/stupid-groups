// StupidGroupsApp.swift
// Stupid Groups

import SwiftUI

@main
struct StupidGroupsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = JamfViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Jamf Pro API Credentials")) {
                        TextField("Jamf Pro URL (e.g. https://myjamf.com)", text: $viewModel.jamfUrl)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        TextField("Username", text: $viewModel.username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        SecureField("Password", text: $viewModel.password)
                            .textContentType(.password)
                    }
                    Section {
                        Button(action: {
                            Task {
                                await viewModel.connect()
                            }
                        }) {
                            Text("Connect to Jamf Pro")
                        }
                        .disabled(!viewModel.canConnect)
                    }
                    
                    if let errorMessage = viewModel.errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundColor(.red)
                        }
                    }
                    
                    if viewModel.isAuthenticated {
                        Section(header: Text("Smart Group Conversion")) {
                            TextField("Smart Group ID", text: $viewModel.smartGroupID)
                                .keyboardType(.numberPad)
                            Picker("Group Type", selection: $viewModel.groupType) {
                                ForEach(JamfViewModel.GroupType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            Button("Convert Smart Group") {
                                Task {
                                    await viewModel.convertSmartGroup()
                                }
                            }
                            .disabled(!viewModel.canConvert)
                        }
                    }
                }
                .navigationTitle("Stupid Groups")
            }
        }
    }
}

// JamfViewModel.swift
import Foundation
import Combine

@MainActor
class JamfViewModel: ObservableObject {
    enum GroupType: String, CaseIterable {
        case computer = "computer-groups"
        case mobileDevice = "mobile-device-groups"
        case user = "user-groups"
        
        var displayName: String {
            switch self {
            case .computer: return "Computer"
            case .mobileDevice: return "Mobile Device"
            case .user: return "User"
            }
        }
    }
    
    @Published var jamfUrl: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var smartGroupID: String = ""
    @Published var groupType: GroupType = .computer
    
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    
    private var token: String?
    
    var canConnect: Bool {
        !jamfUrl.isEmpty && !username.isEmpty && !password.isEmpty
    }
    
    var canConvert: Bool {
        isAuthenticated && !smartGroupID.isEmpty && Int(smartGroupID) != nil
    }
    
    func connect() async {
        errorMessage = nil
        isAuthenticated = false
        token = nil
        
        guard let url = URL(string: jamfUrl) else {
            errorMessage = "Invalid Jamf Pro URL."
            return
        }
        let authUrl = url.appendingPathComponent("/api/v1/auth/token")
        
        var request = URLRequest(url: authUrl)
        request.httpMethod = "POST"
        
        let credentials = "\(username):\(password)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            errorMessage = "Failed to encode credentials."
            return
        }
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid server response."
                return
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
                token = tokenResponse.token
                isAuthenticated = true
            } else if httpResponse.statusCode == 401 {
                errorMessage = "Unauthorized: Invalid username or password."
            } else {
                errorMessage = "Failed to authenticate. Status code: \(httpResponse.statusCode)"
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
    }
    
    func convertSmartGroup() async {
        errorMessage = nil
        
        guard let token = token else {
            errorMessage = "Not authenticated."
            return
        }
        
        guard let jamfBaseURL = URL(string: jamfUrl) else {
            errorMessage = "Invalid Jamf Pro URL."
            return
        }
        
        guard let groupId = Int(smartGroupID) else {
            errorMessage = "Smart Group ID must be a number."
            return
        }
        
        let smartGroupEndpoint = "/api/v1/\(groupType.rawValue)/\(groupId)"
        let url = jamfBaseURL.appendingPathComponent(smartGroupEndpoint)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid server response."
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    errorMessage = "Smart Group not found."
                } else if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                    errorMessage = "Permission denied or not authenticated."
                } else {
                    errorMessage = "Failed to fetch smart group. Status code: \(httpResponse.statusCode)"
                }
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let smartGroup = try decoder.decode(SmartGroup.self, from: data)
            
            // Create static group with the same name, description, and members
            try await createStaticGroup(from: smartGroup, baseURL: jamfBaseURL, token: token)
            
        } catch {
            errorMessage = "Network or parsing error: \(error.localizedDescription)"
        }
    }
    
    private func createStaticGroup(from smartGroup: SmartGroup, baseURL: URL, token: String) async throws {
        // Construct static group payload
        let staticGroup = StaticGroup(
            name: smartGroup.name,
            description: smartGroup.description ?? "",
            isSmart: false,
            criteria: [],
            computers: groupType == .computer ? smartGroup.computers ?? [] : nil,
            mobileDevices: groupType == .mobileDevice ? smartGroup.mobileDevices ?? [] : nil,
            users: groupType == .user ? smartGroup.users ?? [] : nil,
            nesting: nil
        )
        
        let endpoint = "/api/v1/\(groupType.rawValue)"
        let url = baseURL.appendingPathComponent(endpoint)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try encoder.encode(staticGroup)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            errorMessage = "Invalid server response."
            return
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            errorMessage = "Static group created successfully."
        } else if httpResponse.statusCode == 403 {
            errorMessage = "Permission denied: cannot create static group."
        } else {
            let bodyString = String(data: data, encoding: .utf8) ?? "No response body"
            errorMessage = "Failed to create static group. Status code: \(httpResponse.statusCode). Response: \(bodyString)"
        }
    }
}

// Models.swift
import Foundation

struct TokenResponse: Codable {
    let token: String
}

struct SmartGroup: Codable {
    let id: Int
    let name: String
    let description: String?
    let isSmart: Bool
    let criteria: [Criterion]?
    let computers: [Computer]?
    let mobileDevices: [MobileDevice]?
    let users: [User]?
    let nesting: Nesting?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, criteria, computers, users, nesting
        case isSmart = "is_smart"
        case mobileDevices = "mobile_devices"
    }
}

struct Criterion: Codable {
    let name: String
    let value: String
    let operatorType: String
    
    enum CodingKeys: String, CodingKey {
        case name, value
        case operatorType = "operator"
    }
}

struct Computer: Codable, Identifiable {
    let id: Int
    let name: String
}

struct MobileDevice: Codable, Identifiable {
    let id: Int
    let name: String
}

struct User: Codable, Identifiable {
    let id: Int
    let name: String
}

struct Nesting: Codable {
    let join: String
    let groups: [NestGroup]
}

struct NestGroup: Codable {
    let id: Int
    let name: String
}

struct StaticGroup: Codable {
    let name: String
    let description: String
    let isSmart: Bool
    let criteria: [Criterion]
    let computers: [Computer]?
    let mobileDevices: [MobileDevice]?
    let users: [User]?
    let nesting: Nesting?
    
    enum CodingKeys: String, CodingKey {
        case name, description, criteria, computers, users, nesting
        case isSmart = "is_smart"
        case mobileDevices = "mobile_devices"
    }
}
