import SwiftUI

struct MainView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @EnvironmentObject private var dataService: DataSourceService
    @EnvironmentObject private var realTimeDataSource: RealtimeDataService

    var body: some View {
        if dataService.datasource != nil {
            OrientationAdaptiveView {
                GeometryReader { geom in
                    VStack(spacing: 24) {
                        ZStack(alignment: .topTrailing) {
                            IndicatorView(realTimeDataSource)
                                .frame(maxWidth: .infinity, maxHeight: geom.size.height * 0.3 - 12)
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(prefs.theme.indicatorIconColor)
                                    .padding(.top, 8)
                                    .padding(.trailing, 8 + 8)
                            }
                            .padding(0)
                        }
                        GraphView(realTimeDataSource)
                            .frame(maxWidth: .infinity, maxHeight: geom.size.height * 0.7 - 12)
                    }
                    .padding(0)
                }
            } landscape: {
                ZStack(alignment: .top) {
                    GraphView(realTimeDataSource)
                    HStack(alignment: .top) {
                        if let value = realTimeDataSource.currentValue {
                            Text(String(format: "%.1f", value))
                                .font(.title2)
                                .padding(8)
                                .foregroundStyle(Color.black)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(value < 4 || value > 7 ? Color.red : Color.green)
                                )
                                .padding()
                        }
                        Spacer()
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(prefs.theme.accentColor)
                                .padding(.top, 7)
                                .padding(.trailing, 8 + 16)
                        }
                        .padding(0)
                    }
                }
            }
        }
    }
}
