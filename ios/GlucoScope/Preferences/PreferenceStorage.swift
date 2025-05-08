import Foundation

class PreferenceStorage<Value>: ObservableObject where Value: Codable & Equatable {
    private let key: SugarScopePreferenceKey
    private let defaultValue: Value

    @Published var value: Value {
        didSet {
            guard oldValue != value else { return }
            do {
                let data = try JSONEncoder().encode(value)
                UserDefaults.standard.set(data, forKey: key.rawValue)
            } catch {
                print("Failed to encode \(value) for key \(key): \(error)")
            }
        }
    }

    init(key: SugarScopePreferenceKey, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue

        if let data = UserDefaults.standard.data(forKey: key.rawValue),
           let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            self.value = decoded
        } else {
            self.value = defaultValue
        }
    }
}
