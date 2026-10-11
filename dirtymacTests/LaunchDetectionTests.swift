import XCTest
import AppKit
@testable import dirtymac

final class LaunchDetectionTests: XCTestCase {
    private func openApplicationEvent(propData: OSType?) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let propData {
            event.setParam(NSAppleEventDescriptor(enumCode: propData), forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    func testRecognisesALoginItemLaunch() {
        XCTAssertTrue(AppDelegate.isLoginItemLaunch(openApplicationEvent(propData: OSType(keyAELaunchedAsLogInItem))))
    }

    func testOtherLaunchesAreNotLoginItems() {
        XCTAssertFalse(AppDelegate.isLoginItemLaunch(nil))
        XCTAssertFalse(AppDelegate.isLoginItemLaunch(openApplicationEvent(propData: nil)))
        XCTAssertFalse(AppDelegate.isLoginItemLaunch(openApplicationEvent(propData: OSType(keyAELaunchedAsServiceItem))))
        let openDocuments = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        openDocuments.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertFalse(AppDelegate.isLoginItemLaunch(openDocuments))
    }

    func testOnlyManualDefaultLaunchesShowThePanel() {
        let key = NSApplication.launchIsDefaultUserInfoKey
        XCTAssertFalse(AppDelegate.isUserInitiatedLaunch(loginItem: true, userInfo: [key: true]))
        XCTAssertFalse(AppDelegate.isUserInitiatedLaunch(loginItem: false, userInfo: [key: false]))
        XCTAssertTrue(AppDelegate.isUserInitiatedLaunch(loginItem: false, userInfo: nil))
        XCTAssertTrue(AppDelegate.isUserInitiatedLaunch(loginItem: false, userInfo: [key: true]))
    }
}
