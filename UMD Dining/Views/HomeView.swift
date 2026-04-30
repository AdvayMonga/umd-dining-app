import SwiftData
import SwiftUI

private struct StationNavData: Hashable {
    let station: String
    let diningHallId: String
    let diningHallName: String
    let selectedDate: Date
    let selectedMealPeriod: String
}

struct HomeView: View {
    @Binding var tabResetID: UUID
    @State private var viewModel: HomeViewModel
    @State private var showSearch = false
    @State private var showFilter = false
    @State private var selectedItem: MenuItem?
    @State private var selectedStation: StationNavData?
    @Namespace private var namespace
    @Namespace private var mealPickerNS

    // Stable anchor for week strip — today at start of session
    private let calendarAnchor = Calendar.current.startOfDay(for: Date())

    init(tabResetID: Binding<UUID>, initialHallId: String) {
        self._tabResetID = tabResetID
        self._viewModel = State(initialValue: HomeViewModel(selectedHallId: initialHallId))
    }

    private var activeFilterCount: Int {
        (viewModel.filterVegan ? 1 : 0) +
        (viewModel.filterVegetarian ? 1 : 0) +
        (viewModel.filterHalal ? 1 : 0) +
        (viewModel.filterGlutenFree ? 1 : 0) +
        (viewModel.filterDairyFree ? 1 : 0) +
        (viewModel.filterHighProtein ? 1 : 0) +
        viewModel.filterAllergens.count
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    header
                    weekStrip
                    mealPicker
                    content
                }
                .background(Color.umdBackground)
                .navigationDestination(item: $selectedItem) { item in
                    NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station, diningHallName: viewModel.diningHallName(for: item.diningHallId), source: "home", tags: item.tags)
                        .navigationTransition(.zoom(sourceID: item.recNum, in: namespace))
                }
                .navigationDestination(item: $selectedStation) { data in
                    StationPageView(
                        station: data.station,
                        diningHallId: data.diningHallId,
                        diningHallName: data.diningHallName,
                        initialItems: viewModel.itemsForStation(station: data.station, hallId: data.diningHallId),
                        initialDate: data.selectedDate,
                        initialMealPeriod: data.selectedMealPeriod
                    )
                    .navigationTransition(.zoom(sourceID: "\(data.station)-\(data.diningHallId)", in: namespace))
                }
                .sheet(isPresented: $showFilter) {
                    FilterOverlay(
                        filterVegetarian: $viewModel.filterVegetarian,
                        filterVegan: $viewModel.filterVegan,
                        filterHalal: $viewModel.filterHalal,
                        filterGlutenFree: $viewModel.filterGlutenFree,
                        filterDairyFree: $viewModel.filterDairyFree,
                        filterHighProtein: $viewModel.filterHighProtein,
                        filterAllergens: $viewModel.filterAllergens,
                        onDismiss: {
                            showFilter = false
                            Task { await viewModel.loadMenus() }
                        }
                    )
                }
                .task {
                    viewModel.autoSelectMealPeriod()
                    await viewModel.loadMenus()
                }
                .onChange(of: viewModel.selectedDate) {
                    Task { await viewModel.loadMenus() }
                }
            }

            if showSearch {
                SearchOverlay(
                    menuItems: viewModel.allItems,
                    hallNames: viewModel.diningHallNames,
                    selectedDate: viewModel.selectedDate,
                    selectedMealPeriod: viewModel.selectedMealPeriod,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) { showSearch = false }
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .id(tabResetID)
        .onChange(of: tabResetID) {
            showSearch = false
            showFilter = false
            Task { await viewModel.syncPrefsAndReloadIfNeeded() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("UMD Dining")
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(Color.umdRed)

            Spacer()

            Button { showFilter = true } label: {
                ZStack {
                    if activeFilterCount > 0 {
                        Circle()
                            .fill(Color.umdRed)
                            .frame(width: 8, height: 8)
                            .offset(x: 6, y: -6)
                    }
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.umdRed)
                        .frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: activeFilterCount)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { showSearch = true }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.umdRed)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        let calendar = Calendar.current
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.selectedDate, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)

                Spacer()

                if !calendar.isDateInToday(viewModel.selectedDate) {
                    Button("Today") {
                        viewModel.selectedDate = calendarAnchor
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.umdRed)
                    .padding(.trailing, 16)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: calendar.isDateInToday(viewModel.selectedDate))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0...6, id: \.self) { offset in
                            let date = calendar.date(byAdding: .day, value: offset, to: calendarAnchor)!
                            let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)
                            WeekDayCell(date: date, isSelected: isSelected, isToday: offset == 0)
                                .onTapGesture { viewModel.selectedDate = date }
                                .id(offset)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onAppear {
                    let offset = calendar.dateComponents([.day], from: calendarAnchor, to: calendar.startOfDay(for: viewModel.selectedDate)).day ?? 0
                    proxy.scrollTo(max(0, min(6, offset)), anchor: .center)
                }
                .onChange(of: viewModel.selectedDate) {
                    let offset = calendar.dateComponents([.day], from: calendarAnchor, to: calendar.startOfDay(for: viewModel.selectedDate)).day ?? 0
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(max(0, min(6, offset)), anchor: .center)
                    }
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Meal Picker

    private var mealPicker: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.availableMealPeriods, id: \.self) { period in
                let isSelected = viewModel.selectedMealPeriod == period
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedMealPeriod = period
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(period)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? Color.umdRed : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        if isSelected {
                            Rectangle()
                                .fill(Color.umdRed)
                                .frame(height: 2)
                                .matchedGeometryEffect(id: "mealUnderline", in: mealPickerNS)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .bottom) {
            Rectangle().fill(Color(.systemGray5)).frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Hall Card

    private var hallCard: some View {
        VStack(spacing: 8) {
            TabView(selection: $viewModel.selectedHallId) {
                ForEach(viewModel.allHallIds, id: \.self) { id in
                    hallCardPage(for: id)
                        .tag(id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 6) {
                ForEach(viewModel.allHallIds, id: \.self) { id in
                    Circle()
                        .fill(id == viewModel.selectedHallId ? Color.umdRed : Color.gray.opacity(0.35))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedHallId)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .onChange(of: viewModel.selectedHallId) {
            viewModel.showDiscovery = false
            Task { await viewModel.loadMenus() }
        }
    }

    private static let hallImageAlignments: [String: Alignment] = [
        "19": .center,
        "51": .top,
        "16": .center
    ]

    private func hallCardPage(for hallId: String) -> some View {
        let status = DiningHallSchedule.all[hallId]?.currentStatus()
        let imageAlignment = Self.hallImageAlignments[hallId] ?? .center
        return GeometryReader { geo in
            ZStack {
                // Photo — width-constrained so alignment: .top actually crops from top
                Color(.systemGray4)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(alignment: imageAlignment) {
                        Image("hall_\(hallId)")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width)
                    }
                    .clipped()

                // Gradient scrim — fixed height so it's the same on every card
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.75), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }

                // Status badge — top-right
                VStack {
                    HStack {
                        Spacer()
                        if let status {
                            statusBadge(status)
                        }
                    }
                    .padding(12)
                    Spacer()
                }

                // Hall name + time — always bottom-left, same padding on every card
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.diningHallName(for: hallId))
                                .font(.inter(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                            if let status, let close = status.dayCloseTime, status.isOpen {
                                Text("Closes at \(close)")
                                    .font(.inter(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            } else if let status, !status.isOpen, let next = status.nextOpenTime {
                                Text("Opens at \(next)")
                                    .font(.inter(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private func statusBadge(_ status: DiningHallSchedule.Status) -> some View {
        let label: String
        let color: Color
        if status.isOpen {
            label = status.isClosingSoon ? "CLOSING SOON" : "OPEN NOW"
            color = status.isClosingSoon ? .orange : .green
        } else {
            label = "CLOSED"
            color = .red
        }
        return Text(label)
            .font(.inter(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView("Loading menus...")
            Spacer()
        } else if let error = viewModel.errorMessage {
            Spacer()
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await viewModel.loadMenus() } }
            }
            Spacer()
        } else if viewModel.displayRows.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No Menu Available",
                systemImage: "fork.knife",
                description: Text("Try another date or meal period.")
            )
            Spacer()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("feedTop")
                    hallCard
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.displayRows) { row in
                            switch row {
                            case .stationHeader(let station, let hallId, _):
                                StationHeaderRow(
                                    station: station,
                                    diningHallName: viewModel.diningHallName(for: hallId),
                                    diningHallId: hallId,
                                    items: viewModel.itemsForStation(station: station, hallId: hallId),
                                    selectedDate: viewModel.selectedDate,
                                    selectedMealPeriod: viewModel.selectedMealPeriod,
                                    namespace: namespace,
                                    onTap: {
                                        selectedStation = StationNavData(
                                            station: station,
                                            diningHallId: hallId,
                                            diningHallName: viewModel.diningHallName(for: hallId),
                                            selectedDate: viewModel.selectedDate,
                                            selectedMealPeriod: viewModel.selectedMealPeriod
                                        )
                                    }
                                )
                            case .seeMore:
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.showDiscovery = true }
                                } label: {
                                    Text("See More Stations")
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundStyle(Color.umdRed)
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(Color(.systemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                        .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                            case .menuItem(let item):
                                FoodItemRow(
                                    item: item,
                                    diningHallName: viewModel.diningHallName(for: item.diningHallId),
                                    onTap: { selectedItem = item }
                                )
                                .matchedTransitionSource(id: item.recNum, in: namespace)
                            }
                        }
                    }
                    .id(viewModel.selectedMealPeriod)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .refreshable { await viewModel.forceReloadMenus() }
                .onChange(of: viewModel.selectedMealPeriod) {
                    // Scroll instantly (no animation) so it doesn't fight the content transition
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { proxy.scrollTo("feedTop", anchor: .top) }
                }
            }
        }
    }
}

// MARK: - Week Day Cell

private struct WeekDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let numFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

    var body: some View {
        VStack(spacing: 5) {
            Text(Self.dayFmt.string(from: date).uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(Self.numFmt.string(from: date))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isSelected ? .white : (isToday ? Color.umdRed : .primary))
        }
        .frame(width: 46, height: 52)
        .background(isSelected ? Color.umdRed : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    HomeView(tabResetID: .constant(UUID()), initialHallId: "19")
        .environment(FavoritesManager.shared)
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
