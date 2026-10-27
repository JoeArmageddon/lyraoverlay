import SwiftUI
import AppKit
import LyraCore

extension Color {
    init(_ c: RGBA) {
        self.init(.sRGB, red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
    }
}

extension RGBA {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Float(ns.redComponent), Float(ns.greenComponent), Float(ns.blueComponent), Float(ns.alphaComponent))
    }
}

extension SettingsModel {
    /// A binding into the settings, for sliders and toggles.
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { self.settings[keyPath: keyPath] = $0 })
    }

    /// Slider bindings are Double; this adapts Float settings.
    func floatBinding(_ keyPath: WritableKeyPath<AppSettings, Float>) -> Binding<Double> {
        Binding(get: { Double(self.settings[keyPath: keyPath]) }, set: { self.settings[keyPath: keyPath] = Float($0) })
    }

    func colorBinding(_ keyPath: WritableKeyPath<AppSettings, RGBA>) -> Binding<Color> {
        Binding(get: { Color(self.settings[keyPath: keyPath]) }, set: { self.settings[keyPath: keyPath] = RGBA($0) })
    }

    /// For optional manual colors: shows `fallback` until the user picks one.
    func optionalColorBinding(_ keyPath: WritableKeyPath<AppSettings, RGBA?>, fallback: RGBA) -> Binding<Color> {
        Binding(get: { Color(self.settings[keyPath: keyPath] ?? fallback) }, set: { self.settings[keyPath: keyPath] = RGBA($0) })
    }
}
