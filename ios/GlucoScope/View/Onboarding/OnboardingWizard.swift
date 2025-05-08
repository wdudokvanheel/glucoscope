import SwiftUI

struct OnboardingWizard: View {
    @State var model: OnboardModel

    init(_ dataService: DataSourceService) {
        self._model = State(initialValue: OnboardModel(dataService))
    }

    var body: some View {
        IntroView()
            .environmentObject(model)
    }
}
