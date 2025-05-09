import SwiftUI
import Combine

@propertyWrapper
struct Preference<Value: Codable & Equatable>: DynamicProperty {
    @ObservedObject private var storage: PreferenceStorage<Value>

    init(key: GlucoScopePreferenceKey, defaultValue: Value) {
        self.storage = PreferenceStorage(key: key, defaultValue: defaultValue)
    }

    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    var projectedValue: ObservedObject<PreferenceStorage<Value>>.Wrapper {
        $storage
    }
    
    var publisher: Published<Value>.Publisher {
        storage.$value
     }
}
