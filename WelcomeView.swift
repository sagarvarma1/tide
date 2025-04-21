import SwiftUI
import CoreLocation

// Make WelcomeView conform to NSObject and CLLocationManagerDelegate
struct WelcomeView: View {
    // Environment variable to dismiss the sheet
    @Environment(\.dismiss) private var dismiss 

    // Flag to determine presentation mode
    var isChangeLocationMode: Bool = false

    @State private var locationName = ""
    @State private var searchResults: [LocationResult] = []
    @State private var isSearching = false
    @State private var selectedLocation: LocationResult?
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var isLoadingNearbyStations = false
    @State private var showLocationPermissionAlert = false
    @State private var didRequestClosestStation = false // Flag for button action
    
    // Use a private instance of the location manager helper
    @StateObject private var locationHelper = LocationHelper()
    
    @AppStorage("hasSelectedLocation") private var hasSelectedLocation = false
    @AppStorage("selectedLocationName") private var selectedLocationName = ""
    @AppStorage("selectedLocationLatitude") private var selectedLocationLatitude = 0.0
    @AppStorage("selectedLocationLongitude") private var selectedLocationLongitude = 0.0
    @AppStorage("selectedLocationStationId") private var selectedLocationStationId = ""
    
    var body: some View {
        // Wrap in NavigationView for title and toolbar in sheet
        NavigationView {
            VStack(spacing: 20) {
                if !isChangeLocationMode {
                    Text("Welcome to Tide")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("To get started, please select your coastal location")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                HStack {
                    TextField("Search location", text: $locationName)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .onChange(of: locationName) { _ in
                            if !locationName.isEmpty {
                                searchLocation()
                            } else {
                                searchResults = []
                            }
                        }
                
                    if isSearching {
                        ProgressView()
                            .padding(.leading, 5)
                    }
                }
                .padding(.horizontal)
                
                Button(action: {
                    print("WelcomeView: 'Use Station Closest to Me' button tapped")
                    isLoadingNearbyStations = true
                    didRequestClosestStation = true // Set the flag
                    locationHelper.requestLocation() // This triggers the flow
                }) {
                    Label("Use Station Closest to Me", systemImage: "location.near.me")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.top, 5)
                .disabled(isLoadingNearbyStations)
                
                if isLoadingNearbyStations {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Finding stations near you...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 5)
                }
                
                if !searchResults.isEmpty {
                    Text(userLocation != nil ? "Nearby Tide Stations:" : "Search Results:")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 5)
                    
                    List(searchResults) { location in
                        Button(action: {
                            self.selectLocation(location)
                        }) {
                            VStack(alignment: .leading) {
                                Text(location.name)
                                    .font(.headline)
                                
                                if userLocation != nil {
                                    let distance = calculateDistance(from: userLocation!, to: location.coordinate)
                                    Text(String(format: "%.1f miles away", distance))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else {
                                    Text("Station ID: \(location.id)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 250)
                    .padding(.horizontal)
                    .listStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.vertical)
            .navigationTitle(isChangeLocationMode ? "Change Location" : "Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isChangeLocationMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss() // Dismiss the sheet
                        }
                    }
                }
            }
            .alert(isPresented: $showLocationPermissionAlert) {
                Alert(
                    title: Text("Location Access Required"),
                    message: Text("To find tide stations near you, please allow location access in your device settings."),
                    dismissButton: .default(Text("OK"))
                )
            }
            // Set up the location helper callbacks
            .onAppear {
                print("WelcomeView appeared. Setting up location helper callbacks.")
                locationHelper.onLocationReceived = { coordinate in
                    print("WelcomeView: Received location callback: \(coordinate)")
                    
                    // Only proceed if the button explicitly requested it
                    if self.didRequestClosestStation {
                        print("WelcomeView: Processing location received due to button press.")
                        // Reset the flag
                        self.didRequestClosestStation = false
                        
                        // Directly fetch and select the closest station
                        TideStationService.shared.nearestStations(userLocation: coordinate) { results in
                             print("WelcomeView (Button Flow): Received \(results.count) nearby stations.")
                             self.isLoadingNearbyStations = false // Stop loading indicator
                             if let closestStation = results.first {
                                  print("WelcomeView (Button Flow): Automatically selecting closest station: \(closestStation.name)")
                                  // Select location (saves and dismisses/completes setup)
                                  self.selectLocation(closestStation)
                             } else {
                                  print("WelcomeView (Button Flow): No nearby stations found.")
                                  // Optionally show an error to the user here
                             }
                        }
                    } else {
                        print("WelcomeView: Ignoring location received (not requested by button).")
                        // Optional: Could update userLocation state here if needed for distance display in manual search results
                        // self.userLocation = coordinate 
                        // self.findNearbyStations(userLocation: coordinate) // <-- We don't want this automatic list population anymore either
                    }
                }
                locationHelper.onPermissionDenied = {
                    print("WelcomeView: Received permission denied callback.")
                    self.isLoadingNearbyStations = false
                    self.didRequestClosestStation = false // Reset flag on denial
                    self.showLocationPermissionAlert = true
                }
                locationHelper.onLocationError = {
                    print("WelcomeView: Received location error callback.")
                    self.isLoadingNearbyStations = false
                    self.didRequestClosestStation = false // Reset flag on error
                    // Optionally show a different error message
                }
            }
        }
    }
    
    // Centralized function to select location and dismiss if needed
    func selectLocation(_ location: LocationResult) {
        print("WelcomeView: Selecting location: \(location.name), ID: \(location.id)")
        selectedLocationName = location.name
        selectedLocationLatitude = location.coordinate.latitude
        selectedLocationLongitude = location.coordinate.longitude
        selectedLocationStationId = location.id
        hasSelectedLocation = true

        if isChangeLocationMode {
            dismiss() // Dismiss the sheet after selection
        }
    }
    
    func searchLocation() {
        print("WelcomeView: Starting text search for '\(locationName)'")
        isSearching = true
        searchResults = []
        userLocation = nil // Clear user location when searching by text
        
        TideStationService.shared.searchStations(query: locationName) { results in
            print("WelcomeView: Received \(results.count) results for text search '\(locationName)'")
            self.searchResults = results
            self.isSearching = false
        }
    }
    
    func findNearbyStations(userLocation: CLLocationCoordinate2D) {
        print("WelcomeView: Finding nearby stations for location: \(userLocation)")
        TideStationService.shared.nearestStations(userLocation: userLocation) { results in
            print("WelcomeView: Received \(results.count) nearby stations.")
            self.searchResults = results
            self.isLoadingNearbyStations = false
            
            // Automatically PRE-SELECT the first result (closest station)
            // The user will then tap 'Confirm Location'
            if let closestStation = results.first {
                 print("WelcomeView: Automatically pre-selecting closest station: \(closestStation.name)")
                 // self.selectLocation(closestStation) // DON'T automatically select and dismiss
                 self.selectedLocation = closestStation // SET the state to show confirmation box
            }
        }
    }
    
    func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distanceInMeters = fromLocation.distance(from: toLocation)
        let distanceInMiles = distanceInMeters / 1609.344 // Convert meters to miles
        return distanceInMiles
    }
}

// Helper class to encapsulate CLLocationManager logic
class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    var onLocationReceived: ((CLLocationCoordinate2D) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onLocationError: (() -> Void)?
    
    override init() {
        super.init()
        print("LocationHelper: Initialized")
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        let status = locationManager.authorizationStatus
        print("LocationHelper: Requesting location. Status: \(status.rawValue)")
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("LocationHelper: Permission granted. Requesting location update.")
            locationManager.requestLocation() // Request a one-time location update
        case .notDetermined:
            print("LocationHelper: Permission not determined. Requesting authorization.")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            print("LocationHelper: Permission restricted or denied.")
            onPermissionDenied?()
        @unknown default:
            print("LocationHelper: Unknown authorization status.")
            onPermissionDenied?()
        }
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            print("LocationHelper: Did update locations: \(location.coordinate)")
            onLocationReceived?(location.coordinate)
        } else {
            print("LocationHelper: Did update locations but received empty array.")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationHelper: Did fail with error: \(error.localizedDescription)")
        onLocationError?()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("LocationHelper: Did change authorization status: \(status.rawValue)")
        // Handle changes in authorization status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("LocationHelper: Authorization granted in change handler. Requesting location update.")
            locationManager.requestLocation() // Request location now that permission is granted
        case .restricted, .denied:
            print("LocationHelper: Authorization restricted or denied in change handler.")
            onPermissionDenied?()
        default:
            print("LocationHelper: Authorization status changed to other state: \(status.rawValue)")
            break // Ignore other states like notDetermined
        }
    }
}

#Preview {
    WelcomeView()
} 