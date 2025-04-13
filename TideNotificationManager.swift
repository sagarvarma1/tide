import Foundation
import UserNotifications
import CoreLocation

class TideNotificationManager: NSObject, ObservableObject {
    static let shared = TideNotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleTideNotifications(location: String, nextLowTide: Date, nextHighTide: Date) {
        cancelAllPendingNotifications()
        
        // Schedule notification for low tide (30 minutes before)
        scheduleNotification(
            id: "lowTide-\(nextLowTide.timeIntervalSince1970)",
            title: "Low Tide Alert",
            body: "Low tide at \(location) in 30 minutes",
            timeInterval: nextLowTide.timeIntervalSinceNow - (30 * 60) // 30 minutes before
        )
        
        // Schedule notification for high tide (30 minutes before)
        scheduleNotification(
            id: "highTide-\(nextHighTide.timeIntervalSince1970)",
            title: "High Tide Alert",
            body: "High tide at \(location) in 30 minutes",
            timeInterval: nextHighTide.timeIntervalSinceNow - (30 * 60) // 30 minutes before
        )
    }
    
    private func scheduleNotification(id: String, title: String, body: String, timeInterval: TimeInterval) {
        // Only schedule if time is in the future
        guard timeInterval > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    func cancelAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension TideNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

// MARK: - Tide Service Error
enum TideServiceError: Error, LocalizedError {
    case invalidLocation
    case networkError
    case dataNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidLocation:
            return "Invalid coastal location"
        case .networkError:
            return "Unable to connect to tide service"
        case .dataNotAvailable:
            return "Tide data not available for this location"
        }
    }
}

// MARK: - Tide API Service (Facade)
class TideService {
    static let shared = TideService()
    
    private init() {}
    
    func fetchTideData(latitude: Double, longitude: Double, completion: @escaping (Result<TideData, Error>) -> Void) {
        // Get the station ID from UserDefaults if available
        if let stationId = UserDefaults.standard.string(forKey: "selectedLocationStationId"), !stationId.isEmpty {
            print("TideService: Found station ID '\(stationId)'. Fetching data from NOAATideService.")
            // Use the NOAA Tide API to get data (using the corrected function name)
            NOAATideService.shared.fetchTideData(stationId: stationId, completion: completion)
        } else {
             print("TideService: No station ID found. Falling back to mock data.")
            // If no station ID is available, use the mock data as a fallback
            fetchMockTideData(latitude: latitude, longitude: longitude, completion: completion)
        }
    }
    
    // Fallback method that uses mock data (for testing or when API is unavailable)
    private func fetchMockTideData(latitude: Double, longitude: Double, completion: @escaping (Result<TideData, Error>) -> Void) {
        // Validate location coordinates
        guard latitude != 0 && longitude != 0 else {
            completion(.failure(TideServiceError.invalidLocation))
            return
        }
        
        // This is a mock that simulates API response
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Randomly simulate an error (1 in 10 chance)
            let shouldSimulateError = Int.random(in: 1...10) == 1
            
            if shouldSimulateError {
                completion(.failure(TideServiceError.networkError))
                return
            }
            
            // Generate mock tide data based on current time
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            
            // Create tide cycle based on time of day and add some randomness
            let isRising = (hour >= 6 && hour < 12) || (hour >= 18 && hour < 24)
            
            // Add some variability based on location
            let locationVariability = (latitude + longitude).truncatingRemainder(dividingBy: 1.0)
            let baseHeight = isRising ? 2.3 : 3.8
            let currentHeight = baseHeight + (locationVariability - 0.5)
            
            let state = isRising ? "Rising" : "Falling"
            
            // Create mock tide data with some variability based on location
            let lowTideHeight = 0.7 + (locationVariability * 0.5)
            let highTideHeight = 5.2 + (locationVariability * 0.5)
            
            let tideData = TideData(
                currentHeight: currentHeight,
                currentState: state,
                nextLowTide: calendar.date(byAdding: .hour, value: isRising ? 6 : 12, to: now)!,
                lastLowTide: calendar.date(byAdding: .hour, value: isRising ? -6 : -1, to: now)!,
                nextHighTide: calendar.date(byAdding: .hour, value: isRising ? 1 : 6, to: now)!,
                lastHighTide: calendar.date(byAdding: .hour, value: isRising ? -12 : -6, to: now)!,
                nextLowTideHeight: lowTideHeight,
                lastLowTideHeight: lowTideHeight - 0.1,
                nextHighTideHeight: highTideHeight,
                lastHighTideHeight: highTideHeight + 0.2,
                chartPoints: []
            )
            
            completion(.success(tideData))
        }
    }
}

// Data structures
struct TidePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let type: String // "H" or "L"
}

struct TideData {
    let currentHeight: Double
    let currentState: String
    let nextLowTide: Date
    let lastLowTide: Date
    let nextHighTide: Date
    let lastHighTide: Date
    let nextLowTideHeight: Double
    let lastLowTideHeight: Double
    let nextHighTideHeight: Double
    let lastHighTideHeight: Double
    let chartPoints: [TidePoint]

    // Existing User Defaults Caching Logic
    private static let userDefaultsKey = "cachedTideData"
} 