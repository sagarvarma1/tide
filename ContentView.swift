import SwiftUI
import Charts

struct ContentView: View {
    @AppStorage("selectedLocationName") private var locationName = ""
    @AppStorage("selectedLocationLatitude") private var latitude = 0.0
    @AppStorage("selectedLocationLongitude") private var longitude = 0.0
    @AppStorage("hasSelectedLocation") private var hasSelectedLocation = false
    
    @State private var currentTideState = "Rising"
    @State private var currentTideHeight = 2.3
    @State private var lastLowTide = Date().addingTimeInterval(-3 * 3600) // 3 hours ago
    @State private var nextLowTide = Date().addingTimeInterval(9 * 3600) // 9 hours ahead
    @State private var lastHighTide = Date().addingTimeInterval(-9 * 3600) // 9 hours ago
    @State private var nextHighTide = Date().addingTimeInterval(3 * 3600) // 3 hours ahead
    @State private var lastLowTideHeight = 0.7
    @State private var nextLowTideHeight = 0.8
    @State private var lastHighTideHeight = 5.4
    @State private var nextHighTideHeight = 5.2
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdateTime: Date?
    @State private var chartData: [TidePoint] = []
    @State private var showingChangeLocationSheet = false
    
    // State for chart interaction
    @State private var rawSelectedDate: Date? = nil 
    @State private var selectedHeight: Double? = nil
    
    // Computed property to get the selected date, default to now if nil (for initial line)
    private var currentDateForIndicator: Date {
        rawSelectedDate ?? Date()
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    // 1. Current tide display (MOVED TO TOP)
                    VStack(spacing: 5) {
                        Text("Current Tide at")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text(locationName)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(format: "%.1f", currentTideHeight))
                                .font(.system(size: 60, weight: .bold)) // Reduced font size
                                .minimumScaleFactor(0.5) // Allow text to shrink
                            
                            Text("ft")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                        
                        Text(currentTideState)
                            .font(.title3)
                            .foregroundColor(currentTideState == "Rising" ? .blue : .green)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(currentTideState == "Rising" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            )
                    }
                    .padding()
                    .cornerRadius(15)
                    .padding(.horizontal)

                    // Wrap lower content in a ScrollView
                    ScrollView {
                        VStack(spacing: 20) { // Embed existing content in a new VStack for ScrollView
                            // 2. Tide Graph (NOW IN MIDDLE)
                            if !chartData.isEmpty {
                                Chart(chartData) { point in
                                    // Line connecting all points
                                    LineMark(
                                        x: .value("Time", point.date),
                                        y: .value("Height", point.value)
                                    )
                                    .interpolationMethod(.catmullRom) // Smooth curve
                                    .foregroundStyle(.blue)

                                    // Points marking High/Low Tides
                                    PointMark(
                                        x: .value("Time", point.date),
                                        y: .value("Height", point.value)
                                    )
                                    .symbol(point.type == "H" ? .circle : .diamond) // Different symbols
                                    .foregroundStyle(point.type == "H" ? Color.blue : Color.green)
                                    // .annotation(position: .top) { // Optional: Annotate points
                                    //     Text(String(format: "%.1fft", point.value))
                                    //         .font(.caption)
                                    // }
                                }
                                // Add an explicit rule mark and handle gestures
                                .chartOverlay { proxy in
                                    GeometryReader { geometry in
                                        Rectangle().fill(.clear).contentShape(Rectangle()) // Catch gestures
                                            .gesture(
                                                DragGesture(minimumDistance: 0)
                                                    .onChanged { value in
                                                        let location = value.location
                                                        // Find the date at the drag location
                                                        if let date: Date = proxy.value(atX: location.x) {
                                                            // Clamp date to the chart's visible domain if necessary
                                                            let clampedDate = min(max(date, chartData.first?.date ?? date), chartData.last?.date ?? date)
                                                            rawSelectedDate = clampedDate // Update the raw selected date
                                                            // Interpolate height
                                                            selectedHeight = interpolatedHeight(for: clampedDate, using: chartData)
                                                            // print("Selected Date: \(clampedDate), Height: \(selectedHeight ?? -999)") // Debug print
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        // Clear selection on gesture end
                                                        rawSelectedDate = nil
                                                        selectedHeight = nil
                                                    }
                                            )

                                        // --- Draw Indicator Line ---
                                        let origin = geometry[proxy.plotAreaFrame].origin
                                        // Use computed property for indicator position
                                        let currentX = proxy.position(forX: currentDateForIndicator) ?? 0 
                                        
                                        // Check if the indicator time is within plot area
                                        if currentX >= origin.x && currentX <= origin.x + geometry[proxy.plotAreaFrame].size.width {
                                            Rectangle()
                                                .fill(rawSelectedDate == nil ? .red : .gray) // Red for now, gray for scrub
                                                .frame(width: 1)
                                                .offset(x: currentX - geometry[proxy.plotAreaFrame].minX)
                                        }
                                        
                                        // --- Display Selected Values (Placeholder) ---
                                        if let selectedDate = rawSelectedDate, let height = selectedHeight {
                                            // We will add proper display logic here
                                            Text("Selected: \(selectedDate.formatted(date: .omitted, time: .shortened)) - \(height, specifier: "%.1f")ft")
                                                .font(.caption)
                                                .background(Color.white.opacity(0.7))
                                                .position(x: geometry.size.width / 2, y: 20) // Example position
                                        }
                                    }
                                }
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in // Show marks every 3 hours
                                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                                        AxisGridLine()
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { value in
                                        AxisValueLabel(String(format: "%.0fft", value.as(Double.self) ?? 0))
                                        AxisGridLine()
                                    }
                                }
                                .frame(height: 200)
                                .padding(.horizontal)
                                .padding(.bottom)
                            } else {
                                // Show placeholder if no chart data yet
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 200)
                                    .overlay(Text("Loading Chart..."))
                                    .padding(.horizontal)
                                    .padding(.bottom)
                            }

                            // 3. Tide schedule (NOW AT BOTTOM)
                            VStack(spacing: 15) {
                                Text("Tide Schedule")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                TideInfoRow(title: "Next Low Tide", time: nextLowTide, height: nextLowTideHeight, imageName: "arrow.down")
                                
                                Divider()
                                
                                TideInfoRow(title: "Last Low Tide", time: lastLowTide, height: lastLowTideHeight, imageName: "arrow.down")
                                
                                Divider()
                                
                                TideInfoRow(title: "Next High Tide", time: nextHighTide, height: nextHighTideHeight, imageName: "arrow.up")
                                
                                Divider()
                                
                                TideInfoRow(title: "Last High Tide", time: lastHighTide, height: lastHighTideHeight, imageName: "arrow.up")
                            }
                            .padding()
                            .cornerRadius(15)
                            .padding(.horizontal)
                            
                            if let lastUpdateTime = lastUpdateTime {
                                Text("Last updated: \(dateFormatter.string(from: lastUpdateTime))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal)
                            }
                        } // End of inner VStack for ScrollView
                    } // End of ScrollView
                }
                .padding(.vertical)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingChangeLocationSheet = true
                        } label: {
                            Image(systemName: "map")
                        }
                        .disabled(isLoading)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            loadTideData()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
                .onAppear {
                    // Request notification permissions when the app launches
                    TideNotificationManager.shared.requestNotificationPermission()
                    
                    // Try to load data from UserDefaults first
                    loadCachedTideData()
                    
                    // Then fetch fresh data
                    loadTideData()
                }
                .opacity(isLoading ? 0.6 : 1.0)
                .sheet(isPresented: $showingChangeLocationSheet) {
                    WelcomeView(isChangeLocationMode: true)
                }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                }
            }
        }
    }
    
    private func loadCachedTideData() {
        // Try to load cached tide data from UserDefaults
        if let tideData = TideData.loadFromUserDefaults() {
            // Update the UI with the tide data
            updateUIWithTideData(tideData)
            
            // Set last update time
            if let lastUpdateTimeValue = UserDefaults.standard.object(forKey: "lastUpdateTime") as? TimeInterval {
                lastUpdateTime = Date(timeIntervalSince1970: lastUpdateTimeValue)
            }
        }
    }
    
    private func loadTideData() {
        isLoading = true
        errorMessage = nil
        
        TideService.shared.fetchTideData(latitude: latitude, longitude: longitude) { result in
            isLoading = false
            
            switch result {
            case .success(let tideData):
                // Update the UI with the tide data
                self.updateUIWithTideData(tideData)
                
                // Update the last update time
                self.lastUpdateTime = Date()
                UserDefaults.standard.set(self.lastUpdateTime?.timeIntervalSince1970, forKey: "lastUpdateTime")
                
                // Schedule notifications for the next high and low tides
                TideNotificationManager.shared.scheduleTideNotifications(
                    location: locationName,
                    nextLowTide: tideData.nextLowTide,
                    nextHighTide: tideData.nextHighTide
                )
                
                // Also store the data for background use
                TideBackgroundManager.shared.scheduleBackgroundRefresh()
                
            case .failure(let error):
                self.errorMessage = "Failed to load tide data: \(error.localizedDescription)"
            }
        }
    }
    
    private func updateUIWithTideData(_ tideData: TideData) {
        self.currentTideHeight = tideData.currentHeight
        self.currentTideState = tideData.currentState
        self.nextLowTide = tideData.nextLowTide
        self.lastLowTide = tideData.lastLowTide
        self.nextHighTide = tideData.nextHighTide
        self.lastHighTide = tideData.lastHighTide
        self.nextLowTideHeight = tideData.nextLowTideHeight
        self.lastLowTideHeight = tideData.lastLowTideHeight
        self.nextHighTideHeight = tideData.nextHighTideHeight
        self.lastHighTideHeight = tideData.lastHighTideHeight
        self.chartData = tideData.chartPoints
    }
    
    // Helper function to interpolate height at a specific date from HILO points
    private func interpolatedHeight(for date: Date, using points: [TidePoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        
        // Find points immediately before and after the target date
        var previousPoint: TidePoint? = nil
        var nextPoint: TidePoint? = nil
        
        for point in points {
            if point.date <= date {
                previousPoint = point
            }
            if point.date > date {
                nextPoint = point
                break // Found the next point, no need to continue
            }
        }
        
        // Perform interpolation
        if let prev = previousPoint, let next = nextPoint {
            let totalInterval = next.date.timeIntervalSince(prev.date)
            if totalInterval > 0 { // Avoid division by zero
                let elapsedInterval = date.timeIntervalSince(prev.date)
                let fraction = max(0, min(1, elapsedInterval / totalInterval)) // Clamp between 0 and 1
                return prev.value + fraction * (next.value - prev.value)
            } else {
                return prev.value // Interval is zero, use previous value
            }
        } else if let prev = previousPoint {
            // Date is after the last point in the array
            return prev.value
        } else if let next = nextPoint {
            // Date is before the first point in the array
            return next.value
        } else {
            // Should not happen if points is not empty
            return nil
        }
    }
}

struct TideInfoRow: View {
    let title: String
    let time: Date
    let height: Double
    let imageName: String
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: imageName)
                .font(.headline)
                .foregroundColor(imageName == "arrow.up" ? .blue : .green)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(timeFormatter.string(from: time))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", height))
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("ft")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview {
    ContentView()
}
