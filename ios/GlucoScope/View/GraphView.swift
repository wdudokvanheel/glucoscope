import Foundation
import os
import SwiftUI

struct GraphView: View {
    @EnvironmentObject var prefs: PreferenceService
    @ObservedObject var realTimeDataService: RealtimeDataService

    @State private var showOverlay = false
    @State private var hideOverlayWorkItem: DispatchWorkItem? = nil

    init(_ datasource: RealtimeDataService) {
        self.realTimeDataService = datasource
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                if !realTimeDataService.measurements.isEmpty {
                    ColoredLineGraph(data: realTimeDataService.measurements)
                        .ignoresSafeArea(.all, edges: .leading)
                        .padding(.horizontal, 0)
                        .padding(.trailing, 2)

                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 72))

                        Text("Loading graph data")
                            .fontWeight(.thin)
                    }
                    .foregroundStyle(prefs.theme.accentColor)
                    .frame(maxWidth: .infinity)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation{
                            showOverlay.toggle()
                        }
                        resetHideTimer()
                    }
            )

            if showOverlay {
                GraphOverlayMenu(range: GraphRange(hours: self.realTimeDataService.hours, window: self.realTimeDataService.window)) { range in
                    self.realTimeDataService.hours = range.hours
                    self.realTimeDataService.window = range.window
                    self.realTimeDataService.refresh()

                    resetHideTimer()
                }
//                .opacity(showOverlay ? 1 : 0)
                .transition(.opacity)
            }
        }
        .padding(0)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }

    private func resetHideTimer() {
        hideOverlayWorkItem?.cancel()
        guard showOverlay else { return }

        let workItem = DispatchWorkItem {
            withAnimation {
                showOverlay = false
            }
        }
        hideOverlayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
