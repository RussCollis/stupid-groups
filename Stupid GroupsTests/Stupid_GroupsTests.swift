//
//  Stupid_GroupsTests.swift
//  Stupid GroupsTests
//
//  Created by Michael Levenick on 1/21/19.
//  Copyright © 2019 Michael Levenick. All rights reserved.
//

import XCTest
@testable import Stupid_Groups

class Stupid_GroupsTests: XCTestCase {

    let dataHelper = prepareData()

    func testDeviceDataComputerStaticGroup() {
        let result = dataHelper.deviceData(deviceType: "Computer", conversionType: "Static Group")
        XCTAssertEqual(result, ["computer_group", "computers", "computer", "computergroups"])
    }

    func testDeviceDataComputerAdvancedSearch() {
        let result = dataHelper.deviceData(deviceType: "Computer", conversionType: "Advanced Search")
        XCTAssertEqual(result, ["advanced_computer_search", "computers", "computer", "advancedcomputersearches"])
    }

    func testDeviceDataMobileDeviceStaticGroup() {
        let result = dataHelper.deviceData(deviceType: "Mobile Device", conversionType: "Static Group")
        XCTAssertEqual(result, ["mobile_device_group", "mobile_devices", "mobile_device", "mobiledevicegroups"])
    }

    func testDeviceDataMobileDeviceAdvancedSearch() {
        let result = dataHelper.deviceData(deviceType: "Mobile Device", conversionType: "Advanced Search")
        XCTAssertEqual(result, ["advanced_mobile_device_search", "mobile_devices", "mobile_device", "advancedmobiledevicesearches"])
    }

    func testDeviceDataUserStaticGroup() {
        let result = dataHelper.deviceData(deviceType: "User", conversionType: "Static Group")
        XCTAssertEqual(result, ["user_group", "users", "user", "usergroups"])
    }

    func testDeviceDataUserAdvancedSearch() {
        let result = dataHelper.deviceData(deviceType: "User", conversionType: "Advanced Search")
        XCTAssertEqual(result, ["advanced_user_search", "users", "user", "advancedusersearches"])
    }

    func testParseXML() {
        let xml = "<group><name>All MacBooks</name><site>1</site><id>42</id></group>"
        let name = dataHelper.parseXML(fullXMLString: xml, startTag: "name>", endTag: "</name>")
        let site = dataHelper.parseXML(fullXMLString: xml, startTag: "site>", endTag: "</site>")
        let id = dataHelper.parseXML(fullXMLString: xml, startTag: "id>", endTag: "</id>")

        XCTAssertEqual(name, "All MacBooks")
        XCTAssertEqual(site, "1")
        XCTAssertEqual(id, "42")
    }

    func testXmlToPostStaticGroup() {
        let xmlData = dataHelper.xmlToPost(
            newName: "SG Converted - Test",
            siteID: "1",
            criteria: "<size>0</size>",
            membership: "<computer><id>1</id></computer>",
            conversionType: "Static Group",
            deviceRoot: "computer_group",
            devicePlural: "computers",
            deviceSingular: "computer"
        )
        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            XCTFail("Failed to decode XML data")
            return
        }

        XCTAssertTrue(xmlString.contains("<computer_group>"))
        XCTAssertTrue(xmlString.contains("<name>SG Converted - Test</name>"))
        XCTAssertTrue(xmlString.contains("<is_smart>false</is_smart>"))
        XCTAssertTrue(xmlString.contains("<computers><computer><id>1</id></computer></computers>"))
    }

    func testXmlToPostAdvancedSearch() {
        let xmlData = dataHelper.xmlToPost(
            newName: "SG Converted - Search",
            siteID: "-1",
            criteria: "<size>0</size>",
            membership: "",
            conversionType: "Advanced Search",
            deviceRoot: "advanced_computer_search",
            devicePlural: "computers",
            deviceSingular: "computer"
        )
        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            XCTFail("Failed to decode XML data")
            return
        }

        XCTAssertTrue(xmlString.contains("<advanced_computer_search>"))
        XCTAssertTrue(xmlString.contains("<name>SG Converted - Search</name>"))
        XCTAssertTrue(xmlString.contains("<display_fields>"))
        XCTAssertTrue(xmlString.contains("<name>Computer Name</name>"))
    }

    func testTokenURLs() {
        let tokenURL = dataHelper.createTokenURL(baseURL: "https://myinstance.jamfcloud.com/")
        XCTAssertEqual(tokenURL.absoluteString, "https://myinstance.jamfcloud.com/api/v1/auth/token")

        let invalidateURL = dataHelper.createInvalidateURL(baseURL: "https://myinstance.jamfcloud.com/")
        XCTAssertEqual(invalidateURL.absoluteString, "https://myinstance.jamfcloud.com/api/v1/auth/invalidate-token")

        let getURL = dataHelper.createGETURL(url: "https://myinstance.jamfcloud.com/JSSResource/", deviceType: "Computer", id: "5")
        XCTAssertEqual(getURL.absoluteString, "https://myinstance.jamfcloud.com/JSSResource/computergroups/id/5")

        let postURL = dataHelper.createPOSTURL(url: "https://myinstance.jamfcloud.com/JSSResource/", endpoint: "computergroups")
        XCTAssertEqual(postURL.absoluteString, "https://myinstance.jamfcloud.com/JSSResource/computergroups/id/0")
    }

    func testLogEntryCreation() {
        let entry = LogEntry(type: .success, message: "Group converted successfully")
        XCTAssertEqual(entry.type, .success)
        XCTAssertEqual(entry.message, "Group converted successfully")
    }
}
