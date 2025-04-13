import Foundation
import CoreLocation

// Model for NOAA tide station
struct TideStation: Identifiable, Codable {
    let id: String
    let name: String
    let state: String?
    let latitude: Double
    let longitude: Double
    
    // Convert to our LocationResult model
    func toLocationResult() -> LocationResult {
        let displayName = state != nil ? "\(name), \(state!)" : name
        return LocationResult(
            id: id,
            name: displayName,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }
}

// Sample locations as fallback when API is not available
let sampleLocations: [LocationResult] = [
    LocationResult(id: "9414290", name: "San Francisco, CA", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
    LocationResult(id: "9413450", name: "Monterey Bay, CA", coordinate: CLLocationCoordinate2D(latitude: 36.6002, longitude: -121.8947)),
    LocationResult(id: "9413470", name: "Santa Cruz, CA", coordinate: CLLocationCoordinate2D(latitude: 36.9741, longitude: -122.0308)),
    LocationResult(id: "9410840", name: "Malibu, CA", coordinate: CLLocationCoordinate2D(latitude: 34.0259, longitude: -118.7798)),
    LocationResult(id: "9410840", name: "Santa Monica, CA", coordinate: CLLocationCoordinate2D(latitude: 34.0195, longitude: -118.4912)),
    LocationResult(id: "9410170", name: "San Diego, CA", coordinate: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611)),
    LocationResult(id: "9414131", name: "Half Moon Bay, CA", coordinate: CLLocationCoordinate2D(latitude: 37.4636, longitude: -122.4286)),
    LocationResult(id: "9410665", name: "Huntington Beach, CA", coordinate: CLLocationCoordinate2D(latitude: 33.6595, longitude: -117.9988)),
    LocationResult(id: "9410580", name: "Newport Beach, CA", coordinate: CLLocationCoordinate2D(latitude: 33.6189, longitude: -117.9298)),
    LocationResult(id: "9410230", name: "La Jolla, CA", coordinate: CLLocationCoordinate2D(latitude: 32.8328, longitude: -117.2713))
]

// Service to fetch and manage NOAA tide stations
class TideStationService {
    static let shared = TideStationService()
    
    // Use the more specific URL to fetch only water level stations
    private let stationsURL = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=waterlevels"
    private var allStations: [TideStation] = []
    private var isFetching = false
    // Queue for completion handlers waiting for the fetch to finish
    private var fetchCompletionHandlers: [(Bool) -> Void] = []
    // Queue for actions (like search/nearest) waiting for fetch to finish
    private var pendingActions: [() -> Void] = [] 
    
    private init() {
        print("TideStationService: Initializing")
        loadCachedStations()
        // Fetch only if cache is empty or very old (handled in loadCachedStations)
        if allStations.isEmpty {
             print("TideStationService: Cache empty, triggering initial fetch.")
             fetchTideStations { _ in /* Initial fetch */ }
        }
    }
    
    // Search tide stations by name
    func searchStations(query: String, completion: @escaping ([LocationResult]) -> Void) {
        print("TideStationService: Received search request for query: '\(query)'")
        runWhenReady { [weak self] in
            guard let self = self else { return }
            let filteredStations = self.filterStations(query: query)
            print("TideStationService: Executing search. Found \(filteredStations.count) stations for query '\(query)'.")
            completion(filteredStations)
        }
    }
    
    // Get nearest stations to user location
    func nearestStations(userLocation: CLLocationCoordinate2D, completion: @escaping ([LocationResult]) -> Void) {
        print("TideStationService: Received nearest stations request for \(userLocation)")
        runWhenReady { [weak self] in
            guard let self = self else { return }
            let nearby = self.findNearestStations(to: userLocation)
            print("TideStationService: Executing nearest search. Found \(nearby.count) nearby stations.")
            completion(nearby)
        }
    }
    
    // Helper to queue requests if initial fetch is in progress
    private func runWhenReady(action: @escaping () -> Void) {
        // If not currently fetching and stations are loaded, run immediately
        if !isFetching && !allStations.isEmpty {
            print("TideStationService: Stations ready, running action immediately.")
            action()
        } else if isFetching {
            // If fetching, queue the action to run after fetch completes
            print("TideStationService: Fetch in progress, queueing action.")
            pendingActions.append(action)
        } else {
            // Not fetching, but stations are empty (or cache needs refresh) - trigger fetch and queue action
            print("TideStationService: Stations not ready, triggering fetch and queueing action.")
            pendingActions.append(action)
            // Only trigger fetch if not already triggered by another queued action
            if !isFetching { 
                 fetchTideStations { _ in /* Fetch triggered by queued action */ }
            }
        }
    }

    // Filter stations by name/query
    private func filterStations(query: String) -> [LocationResult] {
        let lowercasedQuery = query.lowercased()
        let filtered = allStations
            .filter { station in
                if lowercasedQuery.isEmpty { return true }
                let name = station.name.lowercased()
                let state = station.state?.lowercased() ?? ""
                return name.contains(lowercasedQuery) || state.contains(lowercasedQuery)
            }
            .map { $0.toLocationResult() }
        return Array(filtered.prefix(20))
    }
    
    // Find stations nearest to user location
    private func findNearestStations(to location: CLLocationCoordinate2D) -> [LocationResult] {
        let sorted = allStations.map { station -> (station: TideStation, distance: CLLocationDistance) in
            let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
            let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let distance = stationLocation.distance(from: userLocation)
            return (station, distance)
        }
        .sorted { $0.distance < $1.distance }
        .map { $0.station.toLocationResult() }
        return Array(sorted.prefix(10))
    }
    
    // Fetch tide stations from NOAA
    private func fetchTideStations(completion: @escaping (Bool) -> Void) {
        guard !isFetching else {
            print("TideStationService: Fetch already in progress, adding completion handler.")
            fetchCompletionHandlers.append(completion)
            return
        }
        
        isFetching = true
        print("TideStationService: Starting fetchTideStations from URL: \(stationsURL)")
        // Add the primary completion handler
        fetchCompletionHandlers.append(completion)
        
        guard let url = URL(string: stationsURL) else {
            print("TideStationService: Invalid stations URL")
            processFetchCompletionHandlers(success: false)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            var success = false
            defer {
                // This block ensures fetch state is reset and handlers are called
                print("TideStationService: Fetch finished. Success: \(success)")
                self.processFetchCompletionHandlers(success: success)
            }
            
            if let error = error {
                print("TideStationService: Network error fetching stations: \(error.localizedDescription)")
                return // Handled by defer block
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("TideStationService: HTTP error fetching stations. Status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return // Handled by defer block
            }
            
            guard let data = data else {
                print("TideStationService: No data received for stations.")
                return // Handled by defer block
            }
            
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(StationsResponse.self, from: data)
                print("TideStationService: Successfully parsed \(response.stations.count) stations from API (type=waterlevels).")
                
                // Map directly since the API endpoint filters for us
                self.allStations = response.stations.map { apiStation in
                    return TideStation(
                        id: apiStation.id,
                        name: apiStation.name,
                        state: apiStation.state,
                        latitude: apiStation.lat,
                        longitude: apiStation.lng
                    )
                }
                
                self.cacheStations()
                print("TideStationService: Stations updated and cached (count: \(self.allStations.count)).")
                success = true // Mark as successful
                
            } catch {
                print("TideStationService: Error parsing stations JSON: \(error)")
                // Success remains false, handled by defer block
            }
        }.resume()
    }
    
    // Process all queued completion handlers and pending actions
    private func processFetchCompletionHandlers(success: Bool) {
        DispatchQueue.main.async { [weak self] in 
            guard let self = self else { return }
            
            // Reset fetching state FIRST
            self.isFetching = false 
            
            // Process completion handlers
            let handlers = self.fetchCompletionHandlers
            self.fetchCompletionHandlers.removeAll()
            print("TideStationService: Processing \(handlers.count) fetch completion handlers. Success: \(success)")
            for handler in handlers {
                handler(success)
            }
            
            // If fetch was successful and stations are loaded, run pending actions
            if success && !self.allStations.isEmpty {
                let actions = self.pendingActions
                self.pendingActions.removeAll()
                print("TideStationService: Running \(actions.count) pending actions.")
                for action in actions {
                    action()
                }
            } else {
                 // If fetch failed, clear pending actions (or handle differently if needed)
                 print("TideStationService: Fetch failed or stations empty, clearing \(self.pendingActions.count) pending actions.")
                 self.pendingActions.removeAll()
                 // Optionally, trigger fallback for pending actions here if needed
            }
        }
    }

    // Cache stations to UserDefaults
    private func cacheStations() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(allStations)
            UserDefaults.standard.set(data, forKey: "cachedTideStations")
            UserDefaults.standard.set(Date(), forKey: "lastStationUpdateTime")
            print("TideStationService: Saved \(allStations.count) stations to cache.")
        } catch {
            print("TideStationService: Error caching tide stations: \(error)")
        }
    }
    
    // Load cached stations from UserDefaults
    private func loadCachedStations() {
        print("TideStationService: Attempting to load stations from cache.")
        if let data = UserDefaults.standard.data(forKey: "cachedTideStations") {
            do {
                let decoder = JSONDecoder()
                let loadedStations = try decoder.decode([TideStation].self, from: data)
                 // Check if cache is older than 7 days
                var needsRefresh = false
                if let lastUpdate = UserDefaults.standard.object(forKey: "lastStationUpdateTime") as? Date {
                    let calendar = Calendar.current
                    if let difference = calendar.dateComponents([.day], from: lastUpdate, to: Date()).day,
                       difference > 7 {
                        print("TideStationService: Station cache is older than 7 days.")
                        needsRefresh = true
                    }
                } else {
                    // If no last update time, consider it needing refresh
                    needsRefresh = true
                }
                
                // Only assign loaded stations if not needing refresh immediately
                if !needsRefresh {
                     self.allStations = loadedStations
                     print("TideStationService: Successfully loaded \(allStations.count) stations from valid cache.")
                } else {
                    print("TideStationService: Cache data exists but needs refresh.")
                    // Don't assign self.allStations yet, let init trigger fetch
                }
               
            } catch {
                print("TideStationService: Error loading cached tide stations: \(error)")
                // Cache is corrupt, clear it if necessary
                UserDefaults.standard.removeObject(forKey: "cachedTideStations")
                UserDefaults.standard.removeObject(forKey: "lastStationUpdateTime")
            }
        } else {
            print("TideStationService: No station data found in cache.")
        }
    }
}

// NOAA API response models
struct StationsResponse: Codable {
    let stations: [APIStation]
}

// APIStation no longer needs tideType as the URL filters it
struct APIStation: Codable {
    let id: String
    let name: String
    let state: String?
    let lat: Double
    let lng: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case state
        case lat = "lat"
        case lng = "lng"
        // Removed tideType coding key
    }
}

// Update our LocationResult model to include the station ID
struct LocationResult: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
} 