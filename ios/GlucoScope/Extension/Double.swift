extension Double {
    func toMmol() -> Double {
        return (self / 18.0182 * 10).rounded() / 10
    }
}
