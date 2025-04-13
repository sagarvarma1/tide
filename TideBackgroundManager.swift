import Foundation
import BackgroundTasks
import SwiftUI

// Manager for handling background tide updates
class TideBackgroundManager {
    static let shared = TideBackgroundManager()
    
    private let backgroundTaskIdentifier = "com.tideapp.refreshTideData"
    
    private init() {}
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Schedule the refresh to happen in approximately 4 hours
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled")
        } catch {
            print("Could not schedule app refresh: \(error.localizedDescription)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh task before this one expires
        scheduleBackgroundRefresh()
        
        // Create a task to ensure task completion
        let taskCancellationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Set the expiration handler
        task.expirationHandler = taskCancellationHandler
        
        // Get the stored location data
        guard let locationName = UserDefaults.standard.string(forKey: "selectedLocationName"),
              let latitude = UserDefaults.standard.object(forKey: "selectedLocationLatitude") as? Double,
              let longitude = UserDefaults.standard.object(forKey: "selectedLocationLongitude") as? Double,
              latitude != 0 && longitude != 0 else {
            task.setTaskCompleted(success: false)
            return
        }
        
        // Perform the data fetch
        TideService.shared.fetchTideData(latitude: latitude, longitude: longitude) { result in
            switch result {
            case .success(let tideData):
                // Update local data storage if needed for app UI
                self.updateLocalTideData(tideData)
                
                // Schedule notifications for the next high and low tides
                TideNotificationManager.shared.scheduleTideNotifications(
                    location: locationName,
                    nextLowTide: tideData.nextLowTide,
                    nextHighTide: tideData.nextHighTide
                )
                
                task.setTaskCompleted(success: true)
                
            case .failure:
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func updateLocalTideData(_ tideData: TideData) {
        // In a real app, you might want to store this data
        // so it's immediately available when the app launches
        let userDefaults = UserDefaults.standard
        
        // Store critical tide information
        userDefaults.set(tideData.currentHeight, forKey: "currentTideHeight")
        userDefaults.set(tideData.currentState, forKey: "currentTideState")
        userDefaults.set(tideData.nextLowTide.timeIntervalSince1970, forKey: "nextLowTideTime")
        userDefaults.set(tideData.nextHighTide.timeIntervalSince1970, forKey: "nextHighTideTime")
        userDefaults.set(tideData.lastLowTide.timeIntervalSince1970, forKey: "lastLowTideTime")
        userDefaults.set(tideData.lastHighTide.timeIntervalSince1970, forKey: "lastHighTideTime")
        userDefaults.set(tideData.nextLowTideHeight, forKey: "nextLowTideHeight")
        userDefaults.set(tideData.nextHighTideHeight, forKey: "nextHighTideHeight")
        userDefaults.set(tideData.lastLowTideHeight, forKey: "lastLowTideHeight")
        userDefaults.set(tideData.lastHighTideHeight, forKey: "lastHighTideHeight")
        userDefaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateTime")
    }
}

// Extension to add loading from UserDefaults
extension TideData {
    static func loadFromUserDefaults() -> TideData? {
        let userDefaults = UserDefaults.standard
        
        guard let currentState = userDefaults.string(forKey: "currentTideState"),
              let nextLowTideTime = userDefaults.object(forKey: "nextLowTideTime") as? TimeInterval,
              let nextHighTideTime = userDefaults.object(forKey: "nextHighTideTime") as? TimeInterval,
              let lastLowTideTime = userDefaults.object(forKey: "lastLowTideTime") as? TimeInterval,
              let lastHighTideTime = userDefaults.object(forKey: "lastHighTideTime") as? TimeInterval else {
            return nil
        }
        
        return TideData(
            currentHeight: userDefaults.double(forKey: "currentTideHeight"),
            currentState: currentState,
            nextLowTide: Date(timeIntervalSince1970: nextLowTideTime),
            lastLowTide: Date(timeIntervalSince1970: lastLowTideTime),
            nextHighTide: Date(timeIntervalSince1970: nextHighTideTime),
            lastHighTide: Date(timeIntervalSince1970: lastHighTideTime),
            nextLowTideHeight: userDefaults.double(forKey: "nextLowTideHeight"),
            lastLowTideHeight: userDefaults.double(forKey: "lastLowTideHeight"),
            nextHighTideHeight: userDefaults.double(forKey: "nextHighTideHeight"),
            lastHighTideHeight: userDefaults.double(forKey: "lastHighTideHeight"),
            chartPoints: []
        )
    }
} 