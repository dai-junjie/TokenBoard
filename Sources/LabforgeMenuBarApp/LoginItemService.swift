import Foundation
import ServiceManagement

struct LoginItemService {
    func enableIfPossible() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }

        do {
            let service = SMAppService.mainApp
            if service.status != .enabled {
                try service.register()
            }
        } catch {
            NSLog("Failed to register launch at login: %@", String(describing: error))
        }
    }
}
