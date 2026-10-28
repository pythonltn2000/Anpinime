import SwiftUI

struct AnimeScheduleView: View {
    @EnvironmentObject private var service: AnimeService
    @State private var selectedDay: DayOfWeek = .current
    @State private var scheduleData: [DayOfWeek: [AnimeScheduleItem]] = [:]
    @State private var loading = true
    @State private var errorMessage: String? = nil
    @State private var selectedAnime: Anime? = nil
    @State private var lastUpdated: Date?

    private let days: [DayOfWeek] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Day selector pill bar
            daySelectorBar
                .padding(.vertical, 8)
                .background(Color(white: 0.08))

            Divider()
            Text("Giờ theo website nguồn").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
            if let error = errorMessage, !scheduleData.isEmpty {
                Text("Không cập nhật được lịch: " + error + (lastUpdated.map { " · Lần cuối: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
                    .font(.caption).foregroundColor(.secondary).padding(8)
            }

            ZStack {
                if loading && scheduleData.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Đang tải lịch chiếu AnimeVietsub…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, scheduleData.isEmpty {
                    EmptyStateView(
                        icon: "wifi.exclamationmark",
                        title: "Không thể tải lịch chiếu",
                        message: error,
                        actionTitle: "Thử lại"
                    ) {
                        Task { await load(forceRefresh: true) }
                    }
                } else {
                    let items = scheduleData[selectedDay] ?? []
                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text("Chưa có lịch phát sóng cho \(selectedDay.fullTitle)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Hãy chọn ngày khác hoặc vuốt xuống để làm mới.")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        scheduleGrid(items)
                    }
                }

                // Hidden NavigationLink for tapping anime
                NavigationLink(
                    destination: selectedAnime.map { AnimeDetailView(anime: $0) },
                    isActive: Binding(
                        get: { selectedAnime != nil },
                        set: { if !$0 { selectedAnime = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            }
        }
        .navigationTitle("Lịch chiếu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await load(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Cập nhật lịch chiếu")
            }
        }
        .task {
            await load(forceRefresh: false)
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    // MARK: - Day Selector Bar
    private var daySelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    let isSelected = day == selectedDay
                    let isToday = day == DayOfWeek.current
                    let count = scheduleData[day]?.count ?? 0

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedDay = day
                        }
                    } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                Text(day.shortTitle)
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))

                                if isToday {
                                    Circle()
                                        .fill(isSelected ? Color.white : Color.red)
                                        .frame(width: 5, height: 5)
                                }
                            }

                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .opacity(isSelected ? 0.95 : 0.6)
                            } else {
                                Text("-")
                                    .font(.system(size: 10))
                                    .opacity(0.4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Color.red : Color.secondary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Schedule Grid
    @ViewBuilder
    private func scheduleGrid(_ items: [AnimeScheduleItem]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 14
            ) {
                ForEach(items.sorted {
                    if $0.airTime.isEmpty != $1.airTime.isEmpty { return !$0.airTime.isEmpty }
                    return $0.airTime.localizedStandardCompare($1.airTime) == .orderedAscending
                }) { item in
                    scheduleCard(item)
                }
            }
            .padding(14)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Schedule Card
    @ViewBuilder
    private func scheduleCard(_ item: AnimeScheduleItem) -> some View {
        Button {
            selectedAnime = item.anime
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: item.anime.imageURL)
                        .aspectRatio(3 / 4, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(10)

                    // Gradient shadow for bottom badges
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .cornerRadius(10)

                    // Badges overlay
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            if !item.airTime.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 9))
                                    Text(item.airTime)
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.72), in: Capsule())
                                .foregroundColor(.white)
                            }

                            Spacer()

                            // Status Badge: "Đã chiếu" vs "Sắp chiếu"
                            let isAired = item.statusText.contains("Đã chiếu")
                            if !item.statusText.isEmpty {
                            Text(item.statusText)
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    isAired ? Color.green.opacity(0.85) : Color.orange.opacity(0.85),
                                    in: Capsule()
                                )
                                .foregroundColor(.white)
                            }
                        }
                        .padding(6)

                        Spacer()

                        // Expected Episode badge
                        if !item.expectedEpisode.isEmpty {
                            Text(item.expectedEpisode.hasPrefix("Tập") ? item.expectedEpisode : "Tập \(item.expectedEpisode)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundColor(.white)
                                .padding(6)
                        }
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)

                // Anime Title
                Text(item.anime.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading
    private func load(forceRefresh: Bool) async {
        if scheduleData.isEmpty || forceRefresh {
            loading = true
        }
        errorMessage = nil
        do {
            let data = try await service.schedule(forceRefresh: forceRefresh)
            scheduleData = data
            lastUpdated = service.scheduleUpdatedAt
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
            service.register(error)
        }
    }
}
