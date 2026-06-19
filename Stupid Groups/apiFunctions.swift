//
//  apiFunctions.swift
//  Stupid Groups
//
//  Created by Michael Levenick on 1/24/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//
//  Updated by Russell Collis on 19/06/2026 to fix authentication for
//  Jamf Pro 11.29. As of Jamf Pro 11.5.0, Basic Authentication can no
//  longer be used against the Classic API directly - it can ONLY be used
//  to request a Bearer Token from /api/v1/auth/token. Every subsequent
//  Classic API call (GET/POST/PUT/DELETE) must use that Bearer Token.
//  See: https://developer.jamf.com/jamf-pro/docs/classic-api-authentication-changes
//

import Foundation

public class API {

    // This function can be used for any GET against the Classic API.
    // Pass in a valid Bearer Token (NOT base64 Basic credentials) and a URL.
    // The token is inserted into the Authorization header.
    public func get(getToken: String, getURL: URL) -> String {

        // Declare a variable to be populated, and set up the HTTP Request with headers
        var stringToReturn = "nil"
        let semaphore = DispatchSemaphore(value: 0)
        let request = NSMutableURLRequest(url: getURL)
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.default
        // Bearer Token replaces Basic auth - required as of Jamf Pro 11.5.0
        configuration.httpAdditionalHeaders = ["Authorization" : "Bearer \(getToken)", "Content-Type" : "text/xml", "Accept" : "text/xml"]
        let session = Foundation.URLSession(configuration: configuration)

        // Completion handler. This is what ensures that the response is good/bad
        // and also what handles the semaphore
        let task = session.dataTask(with: request as URLRequest, completionHandler: {
            (data, response, error) -> Void in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 199 && httpResponse.statusCode <= 299 {
                    // Good response from API
                    stringToReturn = String(decoding: data!, as: UTF8.self)
                    NSLog("[INFO  ]: Successful GET completed by StupidGroups.app")
                    NSLog(response?.description ?? "nil")
                } else {
                    // Bad Response from API
                    stringToReturn = String(decoding: data!, as: UTF8.self)
                    NSLog("[ERROR ]: Failed GET completed by StupidGroups.app")
                    NSLog(response?.description ?? "nil")
                }
                semaphore.signal() // Signal completion to the semaphore
            }
            
            if error != nil {
                NSLog("[FATAL ]: " + error!.localizedDescription)
                stringToReturn = String("[FATAL ]: " + error!.localizedDescription)
                semaphore.signal()
            }
        })
        task.resume() // Kick off the actual GET here
        semaphore.wait() // Wait for the semaphore before moving on to the return value
        return stringToReturn
    }

    // This function can be used for any POST against the Classic API.
    // Pass in a valid Bearer Token (NOT base64 Basic credentials) and a URL.
    // The token is inserted into the Authorization header.
    public func post(postToken: String, postURL: URL, postBody: Data) -> String {

        // Declare a variable to be populated, and set up the HTTP Request with headers
        var stringToReturn = "nil"
        let semaphore = DispatchSemaphore(value: 0)
        let request = NSMutableURLRequest(url: postURL)
        request.httpMethod = "POST"
        request.httpBody = postBody
        let configuration = URLSessionConfiguration.default
        // Bearer Token replaces Basic auth - required as of Jamf Pro 11.5.0
        configuration.httpAdditionalHeaders = ["Authorization" : "Bearer \(postToken)", "Content-Type" : "text/xml", "Accept" : "text/xml"]
        let session = Foundation.URLSession(configuration: configuration)

        // Completion handler. This is what ensures that the response is good/bad
        // and also what handles the semaphore
        let task = session.dataTask(with: request as URLRequest, completionHandler: {
            (data, response, error) -> Void in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 199 && httpResponse.statusCode <= 299 {
                    // Good Response from API
                    stringToReturn = String(decoding: data!, as: UTF8.self)
                    NSLog("[INFO  ]: Successful POST completed by StupidGroups.app")
                    NSLog(response?.description ?? "nil")
                } else {
                    // Bad Response from API
                    stringToReturn = String(decoding: data!, as: UTF8.self)
                    NSLog("[ERROR ]: Failed POST completed by StupidGroups.app")
                    NSLog(response?.description ?? "nil")
                }
                semaphore.signal()
            }
            
            if error != nil {
                NSLog("[FATAL ]: " + error!.localizedDescription)
                stringToReturn = String("[FATAL ]: " + error!.localizedDescription)
                semaphore.signal()
            }
        })
        task.resume() // Kick off the actual GET here
        semaphore.wait()
        return stringToReturn
    }

    // NEW - Requests a Bearer Token from the Jamf Pro API.
    // Pass in base64-encoded "username:password" Basic credentials and the
    // full token endpoint URL ({baseURL}api/v1/auth/token). Basic auth is
    // ONLY valid against this single endpoint as of Jamf Pro 11.5.0 - it is
    // rejected everywhere else in the Classic API.
    //
    // Returns a tuple of (token, expires) on success, or nil on failure.
    // "expires" is parsed from the ISO-8601 timestamp Jamf Pro returns so
    // the caller can proactively refresh the token before it lapses.
    public func getBearerToken(basicCredentials: String, tokenURL: URL) -> (token: String, expires: Date)? {

        var tokenResult: (token: String, expires: Date)? = nil
        let semaphore = DispatchSemaphore(value: 0)
        let request = NSMutableURLRequest(url: tokenURL)
        request.httpMethod = "POST"
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Authorization" : "Basic \(basicCredentials)", "Accept" : "application/json"]
        let session = Foundation.URLSession(configuration: configuration)

        let task = session.dataTask(with: request as URLRequest, completionHandler: {
            (data, response, error) -> Void in

            if let error = error {
                NSLog("[FATAL ]: " + error.localizedDescription)
                semaphore.signal()
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 199 && httpResponse.statusCode <= 299,
                  let data = data else {
                NSLog("[ERROR ]: Failed to obtain Bearer Token from /api/v1/auth/token")
                semaphore.signal()
                return
            }

            // Jamf Pro returns: { "token": "...", "expires": "2026-06-19T15:38:30.736Z" }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["token"] as? String,
                   let expiresString = json["expires"] as? String {

                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    var expiryDate = formatter.date(from: expiresString)

                    // Fall back to a formatter without fractional seconds, just in case
                    if expiryDate == nil {
                        let fallbackFormatter = ISO8601DateFormatter()
                        fallbackFormatter.formatOptions = [.withInternetDateTime]
                        expiryDate = fallbackFormatter.date(from: expiresString)
                    }

                    // If parsing still fails, assume a conservative 25 minute lifetime
                    // (Jamf Pro tokens default to 30 minutes) so the app still functions
                    let safeExpiry = expiryDate ?? Date().addingTimeInterval(25 * 60)

                    tokenResult = (token: token, expires: safeExpiry)
                    NSLog("[INFO  ]: Bearer Token obtained, expires \(safeExpiry)")
                } else {
                    NSLog("[ERROR ]: Bearer Token response did not contain expected JSON fields")
                }
            } catch {
                NSLog("[ERROR ]: Failed to parse Bearer Token JSON response")
            }
            semaphore.signal()
        })
        task.resume()
        semaphore.wait()
        return tokenResult
    }

    // NEW - Invalidates a Bearer Token on app quit, mirroring good practice
    // for short-lived admin tooling. Best-effort only; failures are logged
    // but never block app termination.
    public func invalidateToken(token: String, invalidateURL: URL) {
        let request = NSMutableURLRequest(url: invalidateURL)
        request.httpMethod = "POST"
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Authorization" : "Bearer \(token)"]
        let session = Foundation.URLSession(configuration: configuration)
        let task = session.dataTask(with: request as URLRequest, completionHandler: {
            (_, _, error) -> Void in
            if let error = error {
                NSLog("[WARN  ]: Failed to invalidate Bearer Token: " + error.localizedDescription)
            } else {
                NSLog("[INFO  ]: Bearer Token invalidated on quit.")
            }
        })
        task.resume()
    }

}
