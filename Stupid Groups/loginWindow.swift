//
//  loginWindow.swift
//  Stupid Groups
//
//  Created by Michael Levenick on 1/21/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//
//  Updated by Russell Collis on 19/06/2026 to fix authentication for
//  Jamf Pro 11.29. Basic Authentication can no longer be used directly
//  against the Classic API (e.g. /JSSResource/activationcode) as of
//  Jamf Pro 11.5.0. Username/password are now ONLY used to request a
//  short-lived Bearer Token from /api/v1/auth/token, and that Bearer
//  Token is what gets passed forward to the main view controller.
//

import Foundation
import Cocoa

// This delegate is required to pass the Bearer Token and URLs to the main view.
// UPDATED: now passes a Bearer Token + its expiry + the base server URL +
// the original Basic credentials (kept in memory only, so the main view
// controller can silently re-request a new token if the current one expires
// during a long Pre-Flight Check / Convert session).
protocol DataSentDelegate {
    func userDidAuthenticate(bearerToken: String, tokenExpiry: Date, baseURL: String, jssResourceURL: String, basicCredentials: String)
}

class loginWindow: NSViewController, URLSessionDelegate {

    // Set up defaults and a delegate used for credential/url passing
    let loginDefaults = UserDefaults.standard
    var delegateAuth: DataSentDelegate? = nil

    // Declare outlets used on the login screen
    @IBOutlet weak var txtURLOutlet: NSTextField!
    @IBOutlet weak var txtUserOutlet: NSTextField!
    @IBOutlet weak var txtPassOutlet: NSSecureTextField!
    @IBOutlet weak var spinProgress: NSProgressIndicator!
    @IBOutlet weak var btnSubmitOutlet: NSButton!
    @IBOutlet weak var chkRememberMe: NSButton!
    @IBOutlet weak var chkBypass: NSButton!
    
    var doNotRun: String!
    var baseURL: String!        // e.g. https://instance.jamfcloud.com/  (used for /api/v1/auth/token)
    var serverURL: String!      // e.g. https://instance.jamfcloud.com/JSSResource/  (used for Classic API resources)
    var base64Credentials: String!
    var bearerToken: String!
    var tokenExpiry: Date!
    var verified = false

    // This punctuation variable is used for cleaning thngs up below
    let punctuation = CharacterSet(charactersIn: ".:/")
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Restore the Username to text box if we have a default stored
        if loginDefaults.value(forKey: "UserName") != nil {
            txtUserOutlet.stringValue = loginDefaults.value(forKey: "UserName") as! String
        }
        
        // Restore Prem URL to text box if we have a default stored
        if loginDefaults.value(forKey: "InstanceURL") != nil {
            txtURLOutlet.stringValue = loginDefaults.value(forKey: "InstanceURL") as! String
        }
        
        if ( loginDefaults.value(forKey: "InstanceURL") != nil || loginDefaults.value(forKey: "InstanceURL") != nil ) && loginDefaults.value(forKey: "UserName") != nil {
            if self.txtPassOutlet.acceptsFirstResponder == true {
                self.txtPassOutlet.becomeFirstResponder()
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        preferredContentSize = NSSize(width: 383, height: 420) // Limits resizing of the window
        // If we have a URL and a User stored focus the password field
        if loginDefaults.value(forKey: "InstanceURL") != nil  && loginDefaults.value(forKey: "UserName") != nil {
            self.txtPassOutlet.becomeFirstResponder()
        }
    }
    
    @IBAction func btnSubmit(_ sender: Any) {

        // Clean up extraneous whitespace characters
        txtURLOutlet.stringValue = txtURLOutlet.stringValue.trimmingCharacters(in: CharacterSet.whitespaces)
        txtUserOutlet.stringValue = txtUserOutlet.stringValue.trimmingCharacters(in: CharacterSet.whitespaces)
        txtPassOutlet.stringValue = txtPassOutlet.stringValue.trimmingCharacters(in: CharacterSet.whitespaces)
        
        // Warn the user if they have failed to enter an instancename or prem URL
        if txtURLOutlet.stringValue == "" {
            _ = popPrompt().generalWarning(question: "No Server Info", text: "It appears that you have not entered any information for your Jamf Pro URL. Please enter either a Jamf Cloud instance name, or your full URL if you host your own server.")
            NSLog("[ERROR ]: No server info was entered. Setting doNotRun to 1")
            doNotRun = "1" // Set Do Not Run flag
        }
        
        // Warn the user if they have failed to enter a username
        if txtUserOutlet.stringValue == "" {
            _ = popPrompt().generalWarning(question: "No Username Found", text: "It appears that you have not entered a username for Stupid Groups to use while accessing Jamf Pro. Please enter your username and password, and try again.")
            NSLog("[ERROR ]: No user info was entered. Setting doNotRun to 1")
            doNotRun = "1" // Set Do Not Run flag
        }
        
        // Warn the user if they have failed to enter a password
        if txtPassOutlet.stringValue == "" {
            _ = popPrompt().generalWarning(question: "No Password Found", text: "It appears that you have not entered a password for Stupid Groups to use while accessing Jamf Pro. Please enter your username and password, and try again.")
            NSLog("[ERROR ]: No password info was entered. Setting doNotRun to 1")
            doNotRun = "1" // Set Do Not Run flag
        }
        
        // Move forward with verification if we have not flagged the doNotRun flag
        if doNotRun != "1" {

            // Build BOTH the base server URL (used for /api/v1/auth/token) and the
            // JSSResource URL (used for Classic API calls), cleaning up double slashes.
            // UPDATED: previous version only built the /JSSResource/ URL - the Bearer
            // Token endpoint lives at the server root, not under /JSSResource/.
            var cleanedInput = txtURLOutlet.stringValue
            if cleanedInput.hasSuffix("/") {
                cleanedInput.removeLast()
            }

            if cleanedInput.rangeOfCharacter(from: punctuation) == nil {
                // Bare instance name was entered, e.g. "kpmgukdev" -> Jamf Cloud
                baseURL = "https://\(cleanedInput).jamfcloud.com/"
            } else {
                // Full URL was entered, e.g. "https://jss.kpmg.com"
                baseURL = "\(cleanedInput)/"
            }
            serverURL = "\(baseURL!)JSSResource/"

            btnSubmitOutlet.isHidden = true
            spinProgress.startAnimation(self)
            
            // Concatenate the credentials and base64 encode the resulting string.
            // NOTE: as of Jamf Pro 11.5.0 this Basic credential is ONLY ever sent to
            // /api/v1/auth/token below - it is never sent to any Classic API resource.
            let concatCredentials = "\(txtUserOutlet.stringValue):\(txtPassOutlet.stringValue)"
            let utf8Credentials = concatCredentials.data(using: String.Encoding.utf8)
            base64Credentials = utf8Credentials?.base64EncodedString()

            // MARK - Step 1: Exchange Basic credentials for a Bearer Token
            let tokenURL = prepareData().createTokenURL(baseURL: self.baseURL!)
            guard let tokenResult = API().getBearerToken(basicCredentials: self.base64Credentials!, tokenURL: tokenURL) else {
                // Token request itself failed outright (bad creds, network error, etc.)
                DispatchQueue.main.async {
                    self.spinProgress.stopAnimation(self)
                    self.btnSubmitOutlet.isHidden = false
                    _ = popPrompt().generalWarning(question: "Authentication Failed", text: "Stupid Groups was unable to obtain a Bearer Token from \(self.baseURL!)api/v1/auth/token.\n\nPlease check your username, password, and URL, and try again.\n\nIf you are using a self-signed or built-in SSL certificate, try adding the certificate to your keychain, trusting it, and trying again.")
                    NSLog("[INFO  ]: Invalid authentication attempt - could not obtain Bearer Token.")
                }
                return
            }

            self.bearerToken = tokenResult.token
            self.tokenExpiry = tokenResult.expires

            // MARK - Step 2: Verify the Bearer Token actually has useful permissions
            // by reading the activation code, same approach as the original app.
            // This works far better than looking for a 200 response, because Jamf
            // Now instances do not have an API, but if you run a GET to them, you
            // will always get a 200 response.
            let testURL = prepareData().createAuthURL(url: self.serverURL!)
            let authResponse = API().get(getToken: self.bearerToken!, getURL: testURL)
            print(authResponse)

            if authResponse.contains("<activation_code><organization_name>") {
                NSLog("[INFO  ]: Successful authentication attempt.")
                self.verified = true
                // Store username if remember me is checked
                if self.chkRememberMe.state.rawValue == 1 {
                    self.loginDefaults.set(self.txtUserOutlet.stringValue, forKey: "UserName")
                    self.loginDefaults.set(self.txtURLOutlet.stringValue, forKey: "InstanceURL")
                    self.loginDefaults.set(true, forKey: "Remember")
                    self.loginDefaults.synchronize()

                // Dump the stored defaults if no remember me is checked
                } else {
                    self.loginDefaults.removeObject(forKey: "UserName")
                    self.loginDefaults.removeObject(forKey: "InstanceURL")
                    self.loginDefaults.set(false, forKey: "Remember")
                    self.loginDefaults.synchronize()
                }
                self.spinProgress.stopAnimation(self)
                self.btnSubmitOutlet.isHidden = false

                // Pass the Bearer Token, expiry, URLs, and Basic credentials forward
                // (Basic credentials are kept ONLY in memory, to silently mint a
                // fresh Bearer Token if the current one expires mid-session) and
                // dismiss the login view
                if self.delegateAuth != nil {
                    self.delegateAuth?.userDidAuthenticate(bearerToken: self.bearerToken!, tokenExpiry: self.tokenExpiry!, baseURL: self.baseURL!, jssResourceURL: self.serverURL!, basicCredentials: self.base64Credentials!)
                    self.dismiss(self)
                }
            } else if authResponse.contains("[FATAL ]:"){
                // Display an error message if there was a fatal http error
                DispatchQueue.main.async {
                    self.spinProgress.stopAnimation(self)
                    self.btnSubmitOutlet.isHidden = false
                    if authResponse.contains("SSL error") {
                        _ = popPrompt().generalWarning(question: "Fatal Error", text: "There was a fatal error upon authentication attempt. The error is: " + authResponse + "\n\nIf you are using a self-signed or built-in SSL certificate, try adding the certificate to your keychain, trusting it, and trying again.")
                    } else {
                        _ = popPrompt().generalWarning(question: "Fatal Error", text: "There was a fatal error upon authentication attempt. The error is: " + authResponse)
                    }

                    NSLog("[INFO  ]: Invalid authentication attempt.")

                    // Pass forward the Bearer Token and dismiss view if the "bypass
                    // authentication" checkbox is checked. This is used in
                    // security-conscious organizations where some admins have
                    // minimal permissions and cannot GET the activation code, even
                    // though their Bearer Token is otherwise perfectly valid.
                    if self.chkBypass.state.rawValue == 1 {
                        if self.delegateAuth != nil {
                            self.delegateAuth?.userDidAuthenticate(bearerToken: self.bearerToken!, tokenExpiry: self.tokenExpiry!, baseURL: self.baseURL!, jssResourceURL: self.serverURL!, basicCredentials: self.base64Credentials!)
                            self.dismiss(self)
                        }
                        self.verified = true
                    }
                }
            } else {

                // Display an error message if there is no activation_code tag found
                DispatchQueue.main.async {
                    self.spinProgress.stopAnimation(self)
                    self.btnSubmitOutlet.isHidden = false
                    _ = popPrompt().generalWarning(question: "Invalid Credentials", text: "The credentials you entered do not seem to have sufficient permissions. This could be due to an incorrect user/password, or possibly from insufficient permissions. Stupid Groups tests this against the user's ability to view the Activation Code via the API.")
                    NSLog("[INFO  ]: Invalid authentication attempt.")

                    // Pass forward the Bearer Token and dismiss view if the "bypass
                    // authentication" checkbox is checked. This is used in
                    // security-conscious organizations where some admins have
                    // minimal permissions and cannot GET the activation code, even
                    // though their Bearer Token is otherwise perfectly valid.
                    if self.chkBypass.state.rawValue == 1 {
                        if self.delegateAuth != nil {
                            self.delegateAuth?.userDidAuthenticate(bearerToken: self.bearerToken!, tokenExpiry: self.tokenExpiry!, baseURL: self.baseURL!, jssResourceURL: self.serverURL!, basicCredentials: self.base64Credentials!)
                            self.dismiss(self)
                        }
                        self.verified = true
                    }
                }
            }
        } else {
            // Reset the Do Not Run flag so that on subsequent runs we try the checks again.
            doNotRun = "0"
        }
    }
    
    // This is required to allow un-trusted SSL certificates. Leave it alone.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }

    // This is added because it is actually the only way to quit the app with the sheet view
    // down over the main view controller.
    @IBAction func btnQuit(_ sender: Any) {
        self.dismiss(self)
        NSApplication.shared.terminate(self)
    }
    // Clear stored values such as username and URL
    @IBAction func btnClearStored(_ sender: AnyObject) {
        //Clear all stored values
        txtURLOutlet.stringValue = ""
        txtUserOutlet.stringValue = ""
        txtPassOutlet.stringValue = ""
        if let bundle = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundle)
        }
    }
}
