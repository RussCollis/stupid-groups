//
//  ViewController.swift
//  Stupid Groups
//
//  Created by Michael Levenick on 1/21/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//
//  Updated by Russell Collis on 19/06/2026 to fix authentication for
//  Jamf Pro 11.29. The app now stores a Bearer Token (instead of base64
//  Basic credentials) and uses it for every Classic API call. Because
//  Jamf Pro Bearer Tokens are short-lived (30 minutes by default), a
//  small ensureValidToken() check runs before every GET/POST and silently
//  re-requests a fresh token if fewer than 60 seconds remain - mirroring
//  the token-refresh pattern used elsewhere in KPMG's Jamf tooling.
//

import Cocoa

class ViewController: NSViewController, URLSessionDelegate, DataSentDelegate {
    
    // Declare Variables
    // Many of these are declared globally so they can be easily passed from function to function
    var globalBaseURL: String!          // e.g. https://instance.jamfcloud.com/   (used for token requests)
    var globalServerURL: String!        // e.g. https://instance.jamfcloud.com/JSSResource/  (used for Classic API)
    var globalBearerToken: String!      // current valid Bearer Token
    var globalTokenExpiry: Date!        // when globalBearerToken expires
    var globalBasicCredentials: String! // base64 "user:pass" - kept ONLY in memory, used to silently refresh the token
    var verified = false
    var globalHTTPFunction: String!
    var myURL: URL!
    var globalDebug = "off"
    var smartGroupCriteria: String!
    var smartGroupName: String!
    var newName: String!
    var siteID: String!
    var smartGroupMembership: String!
    var globalSmartGroupXML: String!
    @IBOutlet weak var txtPrefix: NSTextField!


    // Declare outlets for use in the view
    @IBOutlet weak var txtGroupID: NSTextField!
    @IBOutlet weak var popConvertTo: NSPopUpButton!
    @IBOutlet weak var popDeviceType: NSPopUpButton!
    @IBOutlet weak var btnPostOutlet: NSButton!
    @IBOutlet weak var btnGetOutlet: NSButton!
    @IBOutlet weak var txtMainWrapper: NSScrollView!
    @IBOutlet var txtMain: NSTextView!

    // Prepare the segue for the sheet view of the login window to appear
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "segueLogin" {
            let loginWindow: loginWindow = segue.destinationController as! loginWindow
            loginWindow.delegateAuth = self
        }
    }

    // Print some welcome messaging upon loading the view
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 383, height: 420) // Limits resizing of the window
        applyDropDownFontColors()
        printString(header: true, error: false, green: false, fixedPoint: false, lineBreakAfter: true, message: "Welcome to Stupid Groups v1.1")
        printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "\nSometimes your groups get too smart.\n\nStupid Groups is here to help.\n\nConvert groups that rarely change membership to Static Groups, and convert compliance reporting groups that aren't used for scoping to Advanced Searches.\n\nEnter your data above and run a Pre-Flight Check to begin.\n")

        // NEW - Best-effort Bearer Token invalidation when the app quits.
        // Tokens expire on their own after 30 minutes regardless, so failure
        // here is harmless - this is just good housekeeping.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self = self, let token = self.globalBearerToken, let base = self.globalBaseURL else { return }
            let invalidateURL = prepareData().createInvalidateURL(baseURL: base)
            API().invalidateToken(token: token, invalidateURL: invalidateURL)
        }
    }

    // Trigger the actual sheet segue upon the view fully appearing
    // It seems to work better here than in viewDidLoad().
    override func viewWillAppear() {
        super.viewWillAppear()
        performSegue(withIdentifier: "segueLogin", sender: self)
    }

    // I'm relatively certain this is not needed, but I will leave it in and commented for now.
    /*
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
     */

    private func applyDropDownFontColors() {
        let titleColor = NSColor(calibratedRed: 0.921431005, green: 0.9214526415, blue: 0.9214410186, alpha: 1.0)
        applyDropDownFontColor(to: popDeviceType, color: titleColor)
        applyDropDownFontColor(to: popConvertTo, color: titleColor)
    }

    private func applyDropDownFontColor(to popUpButton: NSPopUpButton, color: NSColor) {
        let font = popUpButton.font ?? NSFont.messageFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        for item in popUpButton.itemArray {
            item.attributedTitle = NSAttributedString(string: item.title, attributes: attributes)
        }

        if let selectedTitle = popUpButton.titleOfSelectedItem {
            popUpButton.attributedTitle = NSAttributedString(string: selectedTitle, attributes: attributes)
        }
    }

    // NEW - Ensures the in-memory Bearer Token is still valid before any
    // Classic API call. If fewer than 60 seconds remain (or the token has
    // already expired), silently re-requests a fresh one using the Basic
    // credentials retained from the login screen. Required because Jamf
    // Pro Bearer Tokens expire after 30 minutes by default, and a
    // Pre-Flight Check + Convert workflow can easily run longer than that
    // if the admin is reviewing several groups.
    func ensureValidToken() {
        guard let expiry = globalTokenExpiry else { return }
        let remaining = expiry.timeIntervalSinceNow

        if remaining < 60 {
            NSLog("[AUTH  ]: Bearer Token expiring soon (\(Int(remaining))s remaining) - refreshing...")
            let tokenURL = prepareData().createTokenURL(baseURL: globalBaseURL)
            if let refreshed = API().getBearerToken(basicCredentials: globalBasicCredentials, tokenURL: tokenURL) {
                self.globalBearerToken = refreshed.token
                self.globalTokenExpiry = refreshed.expires
                NSLog("[AUTH  ]: Bearer Token refreshed successfully.")
            } else {
                NSLog("[ERROR ]: Failed to refresh Bearer Token. Subsequent calls may fail with 401.")
            }
        }
    }

    // This is the "Pre-Flight Check" button.
    @IBAction func btnGET(_ sender: Any) {
        // Clear the box on the main view controller, and then print some information.
        clearLog()
        printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "Gathering data about \(popDeviceType.titleOfSelectedItem!) group number \(txtGroupID.stringValue)...\n")
        NSLog("[INFO  ]: Starting GET function.")

        // Make sure our Bearer Token is still valid before calling the API
        ensureValidToken()

        // Prepare a URL to use for the GET call, based on device type and ID
        let getURL = prepareData().createGETURL(url: globalServerURL, deviceType: self.popDeviceType.titleOfSelectedItem!, id: self.txtGroupID.stringValue)
        
        // Pass the URL and Bearer Token into the function to get the response XML back
        let smartGroupXML = API().get(getToken: globalBearerToken, getURL: getURL)

        // I opted to parse the returned data, and look for a <name> tag instead of using the
        // response code, as I have noticed the response code is not always reliable when
        // working with MUT.
        if smartGroupXML.contains("<name>"){
            let deviceData = prepareData().deviceData(deviceType: self.popDeviceType.titleOfSelectedItem!, conversionType: self.popConvertTo.titleOfSelectedItem!)

            // Parse the response XML to gather data needed for concatenation
            self.smartGroupCriteria = prepareData().parseXML(fullXMLString: smartGroupXML, startTag: "criteria>", endTag: "</criteria")
            self.smartGroupName = prepareData().parseXML(fullXMLString: smartGroupXML, startTag: "name>", endTag: "</name")
            self.newName = "\(txtPrefix.stringValue) \(String(describing: self.smartGroupName!))".replacingOccurrences(of: "  ", with: " ")
            self.siteID = prepareData().parseXML(fullXMLString: smartGroupXML, startTag: "site>", endTag: "</site")
            self.smartGroupMembership = prepareData().parseXML(fullXMLString: smartGroupXML, startTag: "\(deviceData[1])>", endTag: "</\(deviceData[1])")
            printString(header: false, error: false, green: true, fixedPoint: false, lineBreakAfter: false, message: "Group Found. ")
            printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "Group name appears to be:\n\"\(self.smartGroupName!)\"\n\nand will be converted to\n\"\(self.newName!)\".\n\nPress the Convert button to continue.")
            readyToRun()
        } else {
            printString(header: false, error: true, green: false, fixedPoint: false, lineBreakAfter: false, message: "It seems an error has occured. ")
            printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "The data gathered by Stupid Groups does not appear to match any existing group. Please try again.")
        }
        NSLog("[INFO  ]: GET function returned: " + smartGroupXML)
    }
    
    @IBAction func btnPOST(_ sender: Any) {
        clearLog()
        printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "Submitting data to create new \(popConvertTo.titleOfSelectedItem!) named \(newName ?? "nil")...\n")
        notReadyToRun()
        NSLog("[INFO  ]: Starting POST function.")

        // Make sure our Bearer Token is still valid before calling the API
        ensureValidToken()

        let deviceData = prepareData().deviceData(deviceType: self.popDeviceType.titleOfSelectedItem!, conversionType: self.popConvertTo.titleOfSelectedItem!)
        
        let xmlToPost = prepareData().xmlToPost(newName: newName, siteID: siteID, criteria: smartGroupCriteria, membership: smartGroupMembership, conversionType: popConvertTo.titleOfSelectedItem!, deviceRoot: deviceData[0], devicePlural: deviceData[1], deviceSingular: deviceData[2])
        let postURL = prepareData().createPOSTURL(url: globalServerURL, endpoint: deviceData[3] )
        let postResponse = API().post(postToken: globalBearerToken, postURL: postURL, postBody: xmlToPost)

        if postResponse.contains("<id>"){
            DispatchQueue.main.async {
                self.clearLog()
            let newID = prepareData().parseXML(fullXMLString: postResponse, startTag: "id>", endTag: "</id")
            self.printString(header: false, error: false, green: true, fixedPoint: false, lineBreakAfter: false, message: "Success! ")
            self.printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "Your group was converted to \(self.popConvertTo.titleOfSelectedItem!), with a name of \(self.newName ?? "nil") and an ID of \(newID).")
            }
        } else if postResponse.contains("Error: Duplicate name"){
            clearLog()
            printString(header: false, error: true, green: false, fixedPoint: false, lineBreakAfter: false, message: "ERROR: Duplicate. ")
            printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "It appears that a \(popConvertTo.titleOfSelectedItem!) with a name of \"\(newName ?? "nil")\" already exists.\n\nIf you have a clustered environment, or JamfCloud, it may take a few minutes for the group to appear in your web GUI after conversion.\n\nIf you would like to replace the old \(popConvertTo.titleOfSelectedItem!), please manually delete it and try again.")
        } else if postResponse.contains("[FATAL ]:") {
            clearLog()
            printString(header: false, error: true, green: false, fixedPoint: false, lineBreakAfter: false, message: "FATAL: ")
            printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "Stupid Groups has encountered a fatal error. " + postResponse)
        } else {
            clearLog()
            printString(header: false, error: true, green: false, fixedPoint: false, lineBreakAfter: false, message: "ERROR: ")
            printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: "An unspecified error has occured. Full API response below:\n\n")
            printString(header: false, error: false, green: false, fixedPoint: true, lineBreakAfter: true, message: postResponse)
        }
        NSLog("[INFO  ]: POST function returned: " + postResponse)
    }

    // This function is required to allow the login window to pass
    // the Bearer Token and URLs forward to the main view controller.
    // UPDATED for the Jamf Pro 11.29 Bearer Token flow - see loginWindow.swift
    func userDidAuthenticate(bearerToken: String, tokenExpiry: Date, baseURL: String, jssResourceURL: String, basicCredentials: String) {
        self.globalBearerToken = bearerToken
        self.globalTokenExpiry = tokenExpiry
        self.globalBaseURL = baseURL
        self.globalServerURL = jssResourceURL
        self.globalBasicCredentials = basicCredentials
        verified = true
    }

    // This function is required to allow the app to communicate with
    // servers who are using non-trusted SSL certificates (built-in/self-signed)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }

    // Set the view to "ready to run" state
    func readyToRun() {
        btnPostOutlet.isHidden = false
        btnGetOutlet.isHidden = true
    }

    // Set the view to require another Pre-Flight Check
    func notReadyToRun() {
        btnGetOutlet.isHidden = false
        btnPostOutlet.isHidden = true
    }

    // This function will append text to the primary log block on the
    // main view controller. You can call this function to append or print
    // text to the log box, and select various formats depending on your use.
    // The bool selectors all overrule each other from left to right
    // for example, if you select TRUE for header, it will ignore "error" "green" and "fixed point"
    // Additional line breaks can be added by including \n in the message string

    func printString(header: Bool, error: Bool, green: Bool, fixedPoint: Bool, lineBreakAfter: Bool, message: String) {
        var stringToPrint = ""
        if lineBreakAfter {
            stringToPrint = message + "\n"
        } else {
            stringToPrint = message
        }
        if header {
            self.txtMain.textStorage?.append(NSAttributedString(string: "\(stringToPrint)", attributes: self.myHeaderAttribute))
        } else if error {
            self.txtMain.textStorage?.append(NSAttributedString(string: "\(stringToPrint)", attributes: self.myFailFontAttribute))
        } else if green {
            self.txtMain.textStorage?.append(NSAttributedString(string: "\(stringToPrint)", attributes: self.myOKFontAttribute))
        } else if fixedPoint {
            self.txtMain.textStorage?.append(NSAttributedString(string: "\(stringToPrint)", attributes: self.myCSVFontAttribute))
        } else {
            self.txtMain.textStorage?.append(NSAttributedString(string: "\(stringToPrint)", attributes: self.myFontAttribute))
        }
        self.txtMain.scrollToEndOfDocument(self)
    }
    // Clears the entire logging text field
    func clearLog() {
        self.txtMain.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: self.myFontAttribute))
    }

    // Declare format for various output fonts for the end user to see.
    // These are the font formats called by the printString function.
    let myFontAttribute = [ NSAttributedString.Key.font: NSFont(name: "Helvetica Neue Thin", size: 14.0)! ]
    let myHeaderAttribute = [ NSAttributedString.Key.font: NSFont(name: "Helvetica Neue Thin", size: 20.0)! ]
    let myOKFontAttribute = [
        NSAttributedString.Key.font: NSFont(name: "Helvetica Neue Thin", size: 14.0)!,
        NSAttributedString.Key.foregroundColor: NSColor(deviceRed: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
    ]
    let myFailFontAttribute = [
        NSAttributedString.Key.font: NSFont(name: "Helvetica Neue Thin", size: 14.0)!,
        NSAttributedString.Key.foregroundColor: NSColor(deviceRed: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
    ]
    let myCSVFontAttribute = [ NSAttributedString.Key.font: NSFont(name: "Helvetica Neue Thin", size: 14.0)! ]
    let myAlertFontAttribute = [
        NSAttributedString.Key.font: NSFont(name: "Helvetica Neue Thin", size: 14.0)!,
        NSAttributedString.Key.foregroundColor: NSColor(deviceRed: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
    ]

    // These actions are to reset the pre-flight button with the notreadytorun() function
    // If something changes such as group ID or group type/target type
    @IBAction func popGroupType(_ sender: Any) {
        applyDropDownFontColors()
        notReadyToRun()
    }
    @IBAction func popConvertTo(_ sender: Any) {
        applyDropDownFontColors()
        notReadyToRun()
    }
    @IBAction func txtIDAction(_ sender: Any) {
        notReadyToRun()
    }
    @IBAction func txtPrefixAction(_ sender: Any) {
        notReadyToRun() 
    }

}
