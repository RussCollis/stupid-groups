//
//  xmlBuilder.swift
//  Stupid Groups
//
//  Created by Michael Levenick on 1/21/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//

import Cocoa
import Foundation

public class prepareData {

    // This function returns the data needed for the API call.
    // It returns endpoint strings for the new Jamf Pro API v1 endpoints.
    public func deviceData(deviceType: String, conversionType: String) -> Array<String> {
        var apiData = ["nil","nil","nil","nil"]
        
        // Logic block to determine what data to send back:
        // Mobile Devices
        if deviceType == "Mobile Device" {
            if conversionType == "Advanced Search" {
                apiData = ["advanced_mobile_device_search","mobile-device-advanced-searches","mobile_device","mobile-device-advanced-searches"]
            }
            if conversionType == "Static Group" {
                apiData = ["mobile_device_group","mobile-device-groups","mobile_device","mobile-device-groups"]
            }
            
        // Computers
        } else if deviceType == "Computer" {
            if conversionType == "Advanced Search" {
                apiData = ["advanced_computer_search","computer-advanced-searches","computer","computer-advanced-searches"]
            }
            if conversionType == "Static Group" {
                apiData = ["computer_group","computer-groups","computer","computer-groups"]
            }

        // Users
        } else {
            if conversionType == "Advanced Search" {
                apiData = ["advanced_user_search","user-advanced-searches","user","user-advanced-searches"]
            }
            if conversionType == "Static Group" {
                apiData = ["user_group","user-groups","user","user-groups"]
            }
        }
        return apiData
    }

    // Generate a JSON-serializable dictionary which will be sent to the Jamf Pro API v1 to generate the new object.
    // Pass in all data, and it will determine what is needed based on the conversion type.
    // This replaces the previous xmlToPost function.
    public func jsonToPost(newName: String, siteID: String?, criteria: String?, membership: [Int]?, conversionType: String, devicePlural: String) -> Data? {
        
        var jsonDict: [String: Any] = [:]

        switch conversionType {
        case "Advanced Search":
            // For advanced searches, criteria is expected to be JSON string representing the search criteria.
            // Decode criteria JSON string into object if possible.
            var criteriaObject: Any = [:]
            if let criteria = criteria {
                if let data = criteria.data(using: .utf8) {
                    if let obj = try? JSONSerialization.jsonObject(with: data, options: []) {
                        criteriaObject = obj
                    } else {
                        criteriaObject = criteria // fallback to raw string if JSON parse fails
                    }
                }
            }
            
            jsonDict = [
                "name": newName,
                "criteria": criteriaObject
            ]
            // Add site information if provided (new Jamf API uses optional site object)
            if let siteID = siteID, siteID != "" && siteID.lowercased() != "none" {
                jsonDict["site"] = ["id": Int(siteID) ?? 0]
            }
            
        case "Static Group":
            // For static groups, membership is an array of IDs referring to members.
            jsonDict = [
                "name": newName,
                "isSmart": false,
                devicePlural: membership ?? []
            ]
            if let siteID = siteID, siteID != "" && siteID.lowercased() != "none" {
                jsonDict["site"] = ["id": Int(siteID) ?? 0]
            }
            
        default:
            // Fallback, empty dictionary
            jsonDict = [:]
        }
        
        // Convert dictionary to JSON data and return
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted]) {
            return jsonData
        } else {
            NSLog("[ERROR ]: Failed to serialize JSON for POST request")
            return nil
        }
    }

    // Leslie Helou wrote this sweet little function. It parses XML to gather
    // a substring between two specified tags.
    // Kept for backwards compatibility or XML parsing use elsewhere.
    func parseXML(fullXMLString:String, startTag:String, endTag:String) -> String {
        var rawValue = ""
        if let start = fullXMLString.range(of: startTag),
            let end  = fullXMLString.range(of: endTag, range: start.upperBound..<fullXMLString.endIndex) {
            rawValue.append(String(fullXMLString[start.upperBound..<end.lowerBound]))
        } else {
            // DEBUG HERE
            NSLog("[ERROR ]: Error parsing XML")
            NSLog("[ERROR ]: Start, \(startTag), and end, \(endTag), not found.\n")
        }
        return rawValue
    }
    
    // Remove createAuthURL() as it referenced legacy /activationcode endpoint
    
    // NEW - Create the URL used to request a Bearer Token. Jamf Pro 11.5.0+
    // requires Basic auth to be exchanged for a Bearer Token here BEFORE any
    // Classic API resource (e.g. /JSSResource/...) can be called.
    // Pass in the BASE server URL only, e.g. "https://instance.jamfcloud.com/"
    // (NOT the /JSSResource/ suffixed URL used elsewhere in this class).
    public func createTokenURL(baseURL: String) -> URL {
        let stringURL = "\(baseURL)api/v1/auth/token"
        guard let encodedURL = NSURL(string: stringURL) else {
            fatalError("[ERROR ]: Invalid URL string for token endpoint: \(stringURL)")
        }
        NSLog("[INFO  ]: TOKEN URL CREATED: " + stringURL)
        return encodedURL as URL
    }

    // NEW - Create the URL used to invalidate a Bearer Token on app quit.
    // Pass in the BASE server URL only, as with createTokenURL above.
    public func createInvalidateURL(baseURL: String) -> URL {
        let stringURL = "\(baseURL)api/v1/auth/invalidate-token"
        guard let encodedURL = NSURL(string: stringURL) else {
            fatalError("[ERROR ]: Invalid URL string for invalidate-token endpoint: \(stringURL)")
        }
        NSLog("[INFO  ]: INVALIDATE URL CREATED: " + stringURL)
        return encodedURL as URL
    }
    
    // Create the URL that is used to gather the information from an existing smart group or static group
    // Uses Jamf Pro API v1 endpoints.
    public func createGETURL(url: String, deviceType: String, id: String) -> URL {
        var endpoint = ""
        if deviceType == "Mobile Device" {
            endpoint = "mobile-device-groups"
        } else if deviceType == "Computer" {
            endpoint = "computer-groups"
        } else {
            endpoint = "user-groups"
        }
        let stringURL = "\(url)api/v1/\(endpoint)/\(id)"
        guard let encodedURL = NSURL(string: stringURL) else {
            fatalError("[ERROR ]: Invalid GET URL: \(stringURL)")
        }
        NSLog("[INFO  ]: GET URL CREATED: " + stringURL)
        return encodedURL as URL
    }

    // Create the URL that is used to create the new group or advanced search
    // Uses Jamf Pro API v1 endpoints for POST.
    public func createPOSTURL(url: String, deviceType: String) -> URL {
        var endpoint = ""
        if deviceType == "Mobile Device" {
            endpoint = "mobile-device-groups"
        } else if deviceType == "Computer" {
            endpoint = "computer-groups"
        } else {
            endpoint = "user-groups"
        }
        let stringURL = "\(url)api/v1/\(endpoint)"
        guard let encodedURL = NSURL(string: stringURL) else {
            fatalError("[ERROR ]: Invalid POST URL: \(stringURL)")
        }
        NSLog("[INFO  ]: POST URL CREATED: " + stringURL)
        return encodedURL as URL
    }
}
