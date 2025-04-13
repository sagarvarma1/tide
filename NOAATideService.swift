import Foundation

// Service to fetch tide data from NOAA API
class NOAATideService {
    static let shared = NOAATideService()
    
    private init() {}
    
    // Base URL for NOAA Tides & Currents API
    private let baseURL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
    
    // Date Formatter configured for GMT parsing
    private var gmtDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // GMT/UTC
        formatter.locale = Locale(identifier: "en_US_POSIX") // Crucial for fixed formats
        return formatter
    }()
    
    // Fetch predicted HiLo tide data for a station
    func fetchTideData(stationId: String, completion: @escaping (Result<TideData, Error>) -> Void) {
        
        // Get times for 1 day before and 4 days after (sufficient for HILO)
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Use GMT for date strings
        dayFormatter.dateFormat = "yyyyMMdd"
        
        let calendar = Calendar.current
        let beginDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let endDate = calendar.date(byAdding: .day, value: 4, to: now) ?? now // Fetch 4 days into future

        let beginString = dayFormatter.string(from: beginDate)
        let endString = dayFormatter.string(from: endDate)

        // Create URL for HILO predictions data, requesting data in GMT
        var urlComponents = URLComponents(string: baseURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "station", value: stationId),
            URLQueryItem(name: "product", value: "predictions"), // *** CHANGED product ***
            URLQueryItem(name: "application", value: "TideApp"),
            URLQueryItem(name: "begin_date", value: beginString),
            URLQueryItem(name: "end_date", value: endString),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "time_zone", value: "gmt"), // Request GMT
            URLQueryItem(name: "interval", value: "hilo"), // *** ADDED interval=hilo ***
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = urlComponents?.url else {
            completion(.failure(TideServiceError.invalidLocation))
            return
        }
        
        print("Fetching PREDICTIONS (HiLo) data from: \(url.absoluteString)")
        
        // Fetch the HILO prediction data
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Network error (predictions): \(error.localizedDescription)")
                // Removed fallback - just fail if predictions fail
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("HTTP Error or No Data (predictions). Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                 if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Response (predictions error): \(responseString)")
                 }
                // Removed fallback
                DispatchQueue.main.async { completion(.failure(TideServiceError.networkError)) }
                return
            }
            
            // Parse the JSON response
            do {
                let decoder = JSONDecoder()
                // *** Decode PredictionsResponse directly ***
                let response = try decoder.decode(PredictionsResponse.self, from: data)
                
                if let errorMessage = response.error?.message {
                    print("API Error (predictions): \(errorMessage)")
                     // Removed fallback
                    DispatchQueue.main.async { completion(.failure(TideServiceError.dataNotAvailable)) }
                    return
                }
                
                guard let predictions = response.predictions, !predictions.isEmpty else {
                    print("No predictions data available in response.")
                     // Removed fallback
                    DispatchQueue.main.async { completion(.failure(TideServiceError.dataNotAvailable)) }
                    return
                }
                
                print("Successfully received \(predictions.count) HiLo prediction points.")
                // *** Process the HILO predictions ***
                let tideData = self.processHiLoPredictions(predictions: predictions)
                
                DispatchQueue.main.async {
                    completion(.success(tideData))
                }
            } catch {
                print("Error decoding predictions data: \(error)")
                 // Removed fallback
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    // Process HILO predictions (simpler than processing water level data)
    private func processHiLoPredictions(predictions: [TidePrediction]) -> TideData {
         let now = Date() // Current time in UTC
         let dateFormatter = gmtDateFormatter // Use the GMT formatter
         // No sentinel needed here

         // --- 1. Parse HILO Predictions --- 
         let hiloData = predictions.compactMap { prediction -> (date: Date, value: Double, type: String)? in
             guard let date = dateFormatter.date(from: prediction.time),
                   let value = Double(prediction.value),
                   let type = prediction.type else { 
                 print("Skipping invalid HiLo prediction: \(prediction)")
                 return nil
             }
             return (date, value, type)
         }.sorted { $0.date < $1.date }

         guard !hiloData.isEmpty else {
              print("PROCESS HILO: No valid HiLo points after parsing.")
              return createMockTideData(currentHeight: 0, currentState: "Unknown")
         }

         // --- 2. Determine Current State & Interpolate Height ---
         var previousHilo: (date: Date, value: Double, type: String)?
         var nextHilo: (date: Date, value: Double, type: String)?
         for point in hiloData {
             if point.date <= now { previousHilo = point }
             if point.date > now { nextHilo = point; break } 
         }
         
         var currentState = "Unknown"
         var currentHeight: Double = 0.0 // Default
         
         if let prev = previousHilo, let next = nextHilo {
             // Interpolate height
             let totalInterval = next.date.timeIntervalSince(prev.date)
             if totalInterval > 0 { // Avoid division by zero
                 let elapsedInterval = now.timeIntervalSince(prev.date)
                 let fraction = max(0, min(1, elapsedInterval / totalInterval)) // Clamp between 0 and 1
                 currentHeight = prev.value + fraction * (next.value - prev.value)
                 print("PROCESS HILO: Interpolated current height: \(currentHeight) (Frac: \(fraction))")
             } else {
                 currentHeight = prev.value // If interval is zero, use previous value
             }
             // Determine state based on surrounding HILO types
             currentState = (prev.type == "L" && next.type == "H") ? "Rising" : "Falling"
             // Refined state check (optional): compare interpolated height to previous point
             // currentState = currentHeight >= prev.value ? "Rising" : "Falling" 
         } else if let prev = previousHilo {
             // After the last known HILO point in data
             currentHeight = prev.value 
             currentState = prev.type == "L" ? "Rising" : "Falling" // Extrapolating state
             print("PROCESS HILO: Using last known height: \(currentHeight)")
         } else if let next = nextHilo {
             // Before the first known HILO point in data
             currentHeight = next.value 
             currentState = next.type == "H" ? "Rising" : "Falling" // Extrapolating state
             print("PROCESS HILO: Using next known height: \(currentHeight)")
         } else {
              // Should not happen if hiloData is not empty, but set defaults
              currentHeight = hiloData.first?.value ?? 0.0
              print("PROCESS HILO: Could not determine surrounding points for interpolation.")
         }

         // --- 3. Assign Last/Next High/Low Tides (Directly from HILO data) --- REWRITTEN --- 
         let pastHilo = hiloData.filter { $0.date <= now }
         let futureHilo = hiloData.filter { $0.date > now }

         let lastHighTidePoint = pastHilo.last { $0.type == "H" }
         let lastLowTidePoint = pastHilo.last { $0.type == "L" }
         let nextHighTidePoint = futureHilo.first { $0.type == "H" }
         let nextLowTidePoint = futureHilo.first { $0.type == "L" }

         // Extract values or use nil/0.0
         let lastHighTide = lastHighTidePoint?.date
         let lastHighTideHeight = lastHighTidePoint?.value ?? 0.0
         let lastLowTide = lastLowTidePoint?.date
         let lastLowTideHeight = lastLowTidePoint?.value ?? 0.0
         let nextHighTide = nextHighTidePoint?.date
         let nextHighTideHeight = nextHighTidePoint?.value ?? 0.0
         let nextLowTide = nextLowTidePoint?.date
         let nextLowTideHeight = nextLowTidePoint?.value ?? 0.0

         // Logging the found points
         print("PROCESS HILO: Assigning - Last High: \(lastHighTide?.description ?? "nil") (\(lastHighTideHeight)), Last Low: \(lastLowTide?.description ?? "nil") (\(lastLowTideHeight))")
         print("PROCESS HILO: Assigning - Next High: \(nextHighTide?.description ?? "nil") (\(nextHighTideHeight)), Next Low: \(nextLowTide?.description ?? "nil") (\(nextLowTideHeight))")
         
         // --- 4. Create Result --- 
         let defaultFutureDate = now.addingTimeInterval(6 * 3600)
         let defaultPastDate = now.addingTimeInterval(-6 * 3600)
         
         // Filter points for the chart (e.g., +/- 24 hours from now)
         let chartStartDate = Calendar.current.date(byAdding: .hour, value: -12, to: now) ?? now
         let chartEndDate = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now
         let chartPointsData = hiloData.filter { $0.date >= chartStartDate && $0.date <= chartEndDate }
             .map { TidePoint(date: $0.date, value: $0.value, type: $0.type) }

         return TideData(
             currentHeight: currentHeight, // Use interpolated height
             currentState: currentState,
             nextLowTide: nextLowTide ?? defaultFutureDate,
             lastLowTide: lastLowTide ?? defaultPastDate,
             nextHighTide: nextHighTide ?? defaultFutureDate,
             lastHighTide: lastHighTide ?? defaultPastDate,
             nextLowTideHeight: nextLowTideHeight,
             lastLowTideHeight: lastLowTideHeight,
             nextHighTideHeight: nextHighTideHeight,
             lastHighTideHeight: lastHighTideHeight,
             chartPoints: chartPointsData // Add the points for the chart
         )
     }
    
    // Fallback mock data generation
    private func createMockTideData(currentHeight: Double, currentState: String) -> TideData {
        let now = Date()
        return TideData(
            currentHeight: currentHeight,
            currentState: currentState,
            nextLowTide: now.addingTimeInterval(6 * 3600),
            lastLowTide: now.addingTimeInterval(-6 * 3600),
            nextHighTide: now.addingTimeInterval(12 * 3600),
            lastHighTide: now.addingTimeInterval(-12 * 3600),
            nextLowTideHeight: currentHeight - 2.5,
            lastLowTideHeight: currentHeight - 2.2,
            nextHighTideHeight: currentHeight + 2.5,
            lastHighTideHeight: currentHeight + 2.2,
            chartPoints: [] // No chart points for mock data
        )
    }
}

// --- NOAA API Response Models --- 

struct WaterLevelResponse: Codable {
    let data: [WaterLevelPoint]?
    let error: NOAAError?
}

struct WaterLevelPoint: Codable {
    let t: String  // time (e.g., "2023-10-27 15:00")
    let v: String  // value (water level)
    // Other fields (s, f, q) are optional and ignored for now
}

struct PredictionsResponse: Codable {
    let predictions: [TidePrediction]?
    let error: NOAAError?
}

struct TidePrediction: Codable {
    let time: String // Key is 'time' for predictions
    let value: String // Key is 'value' for predictions
    let type: String? // HILO predictions include 'type' (H or L)
    
    // Adjust coding keys if necessary based on actual API response for predictions
     enum CodingKeys: String, CodingKey {
        case time = "t" // Prediction API uses 't' for time
        case value = "v" // Prediction API uses 'v' for value
        case type
    }
}

struct NOAAError: Codable {
    let message: String
}

// Structure to hold a single point for the chart
// MOVED TO TideNotificationManager.swift
// struct TidePoint: Identifiable { ... }

// Updated TideData structure to include chart points
// MOVED TO TideNotificationManager.swift
// struct TideData { ... }

// ... End of file ... 