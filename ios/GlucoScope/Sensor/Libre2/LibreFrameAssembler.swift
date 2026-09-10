import Foundation

struct LibreFrameAssembler {
    enum AppendResult: Equatable {
        case incomplete(Int)
        case frame(Data)
        case overflow(Int)
    }

    let frameLength: Int
    private(set) var buffer = Data()

    init(frameLength: Int = 46) { self.frameLength = frameLength }

    mutating func append(_ fragment: Data) -> AppendResult {
        guard !fragment.isEmpty else { return .incomplete(buffer.count) }
        let total = buffer.count + fragment.count
        guard total <= frameLength else {
            buffer.removeAll(keepingCapacity: true)
            return .overflow(total)
        }
        buffer.append(fragment)
        guard buffer.count == frameLength else { return .incomplete(buffer.count) }
        let frame = buffer
        buffer.removeAll(keepingCapacity: true)
        return .frame(frame)
    }

    mutating func reset() { buffer.removeAll(keepingCapacity: true) }
}
