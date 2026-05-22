// Auto-generated palette tokens. Do not edit by hand — values are
// regenerated from the design source and manual changes will be lost.

import SwiftUI

public struct GradientStop: Equatable, Sendable {
    public let hex: String
    public let location: Double
}

public struct RGBAColor: Equatable, Sendable {
    public let r: Int
    public let g: Int
    public let b: Int
    public let a: Double

    public var color: Color {
        Color(.sRGB,
              red: Double(r) / 255.0,
              green: Double(g) / 255.0,
              blue: Double(b) / 255.0,
              opacity: a)
    }
}

public struct SchemeTokens: Equatable, Sendable {
    public let key: String
    public let name: String
    public let swatchHex: String
    public let bgHex: String
    public let stripTop: [GradientStop]
    public let stripBottom: [GradientStop]
    public let graticule: RGBAColor
    public let inkHex: String
    public let inkFaintHex: String
    public let inkSubtleHex: String
    public let accentHex: String
    public let accentGlow: RGBAColor
    public let accentRing: RGBAColor
    public let traceHex: String
    public let recHex: String
    public let recGlow: RGBAColor
    public let sparkleHex: String
    public let edge: RGBAColor
    public let edgeStrong: RGBAColor
    public let detailsBg: RGBAColor
    public let bezelHighlight: RGBAColor
    public let bezelShadow: RGBAColor
}

public enum Palette: String, CaseIterable, Sendable {
    case amber
    case carbon
    case slate
    case oxide
    case concrete
    case steel
    case aluminum
    case bone
    case paper
    case porcelain
    case vellum
    case pearl
    case chiffon

    public var tokens: SchemeTokens {
        Self.tokensByKey[rawValue]!
    }

    public static let tokensByKey: [String: SchemeTokens] = [
        "amber": SchemeTokens(
            key: "amber",
            name: "AMBER",
            swatchHex: "E89A3C",
            bgHex: "14181A",
            stripTop: [
                GradientStop(hex: "1F2426", location: 0),
                GradientStop(hex: "1A1F22", location: 0.35),
                GradientStop(hex: "0F1416", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "0D1113", location: 0),
                GradientStop(hex: "161B1E", location: 0.55),
                GradientStop(hex: "1E2528", location: 1),
            ],
            graticule: RGBAColor(r: 232, g: 154, b: 60, a: 0.08),
            inkHex: "E89A3C",
            inkFaintHex: "7A8B85",
            inkSubtleHex: "6B7A75",
            accentHex: "E89A3C",
            accentGlow: RGBAColor(r: 232, g: 154, b: 60, a: 0.5),
            accentRing: RGBAColor(r: 232, g: 154, b: 60, a: 0.06),
            traceHex: "E89A3C",
            recHex: "FF5A4A",
            recGlow: RGBAColor(r: 255, g: 90, b: 74, a: 0.55),
            sparkleHex: "FF5A4A",
            edge: RGBAColor(r: 232, g: 154, b: 60, a: 0.1),
            edgeStrong: RGBAColor(r: 232, g: 154, b: 60, a: 0.28),
            detailsBg: RGBAColor(r: 232, g: 154, b: 60, a: 0.08),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.1),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.45)
        ),
        "carbon": SchemeTokens(
            key: "carbon",
            name: "CARBON",
            swatchHex: "FF9D33",
            bgHex: "0E0F10",
            stripTop: [
                GradientStop(hex: "1A1B1C", location: 0),
                GradientStop(hex: "141516", location: 0.45),
                GradientStop(hex: "08090A", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "060708", location: 0),
                GradientStop(hex: "131415", location: 0.55),
                GradientStop(hex: "1C1D1E", location: 1),
            ],
            graticule: RGBAColor(r: 255, g: 157, b: 51, a: 0.07),
            inkHex: "F0EDE6",
            inkFaintHex: "B8B2A4",
            inkSubtleHex: "8A8478",
            accentHex: "FF9D33",
            accentGlow: RGBAColor(r: 255, g: 157, b: 51, a: 0.4),
            accentRing: RGBAColor(r: 255, g: 157, b: 51, a: 0.06),
            traceHex: "FF9D33",
            recHex: "FF5A4A",
            recGlow: RGBAColor(r: 255, g: 90, b: 74, a: 0.55),
            sparkleHex: "FF5A4A",
            edge: RGBAColor(r: 255, g: 255, b: 255, a: 0.06),
            edgeStrong: RGBAColor(r: 255, g: 157, b: 51, a: 0.32),
            detailsBg: RGBAColor(r: 255, g: 255, b: 255, a: 0.04),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.08),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.55)
        ),
        "slate": SchemeTokens(
            key: "slate",
            name: "SLATE",
            swatchHex: "E5B040",
            bgHex: "363D45",
            stripTop: [
                GradientStop(hex: "424A53", location: 0),
                GradientStop(hex: "3A4148", location: 0.45),
                GradientStop(hex: "2E343A", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "2A3036", location: 0),
                GradientStop(hex: "353C44", location: 0.55),
                GradientStop(hex: "404750", location: 1),
            ],
            graticule: RGBAColor(r: 229, g: 176, b: 64, a: 0.08),
            inkHex: "E5B040",
            inkFaintHex: "8E9AA4",
            inkSubtleHex: "7A8590",
            accentHex: "E5B040",
            accentGlow: RGBAColor(r: 229, g: 176, b: 64, a: 0.4),
            accentRing: RGBAColor(r: 229, g: 176, b: 64, a: 0.06),
            traceHex: "E5B040",
            recHex: "FF6B5A",
            recGlow: RGBAColor(r: 255, g: 107, b: 90, a: 0.5),
            sparkleHex: "FF6B5A",
            edge: RGBAColor(r: 255, g: 255, b: 255, a: 0.1),
            edgeStrong: RGBAColor(r: 229, g: 176, b: 64, a: 0.36),
            detailsBg: RGBAColor(r: 255, g: 255, b: 255, a: 0.05),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.1),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.4)
        ),
        "oxide": SchemeTokens(
            key: "oxide",
            name: "OXIDE",
            swatchHex: "D69862",
            bgHex: "22344A",
            stripTop: [
                GradientStop(hex: "2A3D54", location: 0),
                GradientStop(hex: "233649", location: 0.45),
                GradientStop(hex: "1A2B3E", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "182840", location: 0),
                GradientStop(hex: "233649", location: 0.55),
                GradientStop(hex: "2C405A", location: 1),
            ],
            graticule: RGBAColor(r: 214, g: 152, b: 98, a: 0.08),
            inkHex: "F0E5D0",
            inkFaintHex: "8FA0B0",
            inkSubtleHex: "7A8B9C",
            accentHex: "D69862",
            accentGlow: RGBAColor(r: 214, g: 152, b: 98, a: 0.4),
            accentRing: RGBAColor(r: 214, g: 152, b: 98, a: 0.06),
            traceHex: "D69862",
            recHex: "E85A4A",
            recGlow: RGBAColor(r: 232, g: 90, b: 74, a: 0.5),
            sparkleHex: "E85A4A",
            edge: RGBAColor(r: 214, g: 152, b: 98, a: 0.12),
            edgeStrong: RGBAColor(r: 214, g: 152, b: 98, a: 0.36),
            detailsBg: RGBAColor(r: 255, g: 255, b: 255, a: 0.04),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.08),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.4)
        ),
        "concrete": SchemeTokens(
            key: "concrete",
            name: "CONCRETE",
            swatchHex: "9A6A22",
            bgHex: "B0ADA6",
            stripTop: [
                GradientStop(hex: "BAB7B0", location: 0),
                GradientStop(hex: "ADAAA3", location: 0.6),
                GradientStop(hex: "A09D96", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "A8A59E", location: 0),
                GradientStop(hex: "B0ADA6", location: 0.55),
                GradientStop(hex: "B6B3AC", location: 1),
            ],
            graticule: RGBAColor(r: 154, g: 106, b: 34, a: 0.1),
            inkHex: "3D3528",
            inkFaintHex: "6B6356",
            inkSubtleHex: "5E574B",
            accentHex: "9A6A22",
            accentGlow: RGBAColor(r: 154, g: 106, b: 34, a: 0.16),
            accentRing: RGBAColor(r: 154, g: 106, b: 34, a: 0.05),
            traceHex: "9A6A22",
            recHex: "B23A20",
            recGlow: RGBAColor(r: 178, g: 58, b: 32, a: 0.3),
            sparkleHex: "B23A20",
            edge: RGBAColor(r: 40, g: 30, b: 20, a: 0.16),
            edgeStrong: RGBAColor(r: 40, g: 30, b: 20, a: 0.34),
            detailsBg: RGBAColor(r: 40, g: 30, b: 20, a: 0.05),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.2),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.1)
        ),
        "steel": SchemeTokens(
            key: "steel",
            name: "STEEL",
            swatchHex: "E89A3C",
            bgHex: "BCC3C9",
            stripTop: [
                GradientStop(hex: "C6CCD2", location: 0),
                GradientStop(hex: "BABFC5", location: 0.6),
                GradientStop(hex: "ADB3B9", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "B4BAC0", location: 0),
                GradientStop(hex: "BCC3C9", location: 0.55),
                GradientStop(hex: "C2C8CE", location: 1),
            ],
            graticule: RGBAColor(r: 232, g: 154, b: 60, a: 0.1),
            inkHex: "2A2E32",
            inkFaintHex: "5C6168",
            inkSubtleHex: "4F545B",
            accentHex: "E89A3C",
            accentGlow: RGBAColor(r: 232, g: 154, b: 60, a: 0.18),
            accentRing: RGBAColor(r: 232, g: 154, b: 60, a: 0.06),
            traceHex: "E89A3C",
            recHex: "C43A1C",
            recGlow: RGBAColor(r: 196, g: 58, b: 28, a: 0.3),
            sparkleHex: "C43A1C",
            edge: RGBAColor(r: 20, g: 24, b: 28, a: 0.16),
            edgeStrong: RGBAColor(r: 20, g: 24, b: 28, a: 0.34),
            detailsBg: RGBAColor(r: 20, g: 24, b: 28, a: 0.04),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.3),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.1)
        ),
        "aluminum": SchemeTokens(
            key: "aluminum",
            name: "ALUMINUM",
            swatchHex: "D49236",
            bgHex: "D6DBE0",
            stripTop: [
                GradientStop(hex: "DFE3E8", location: 0),
                GradientStop(hex: "D4D8DD", location: 0.6),
                GradientStop(hex: "C8CDD2", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "CFD4D9", location: 0),
                GradientStop(hex: "D6DBE0", location: 0.55),
                GradientStop(hex: "DDE2E7", location: 1),
            ],
            graticule: RGBAColor(r: 212, g: 146, b: 54, a: 0.1),
            inkHex: "2A2E32",
            inkFaintHex: "5C6168",
            inkSubtleHex: "4F545B",
            accentHex: "D49236",
            accentGlow: RGBAColor(r: 212, g: 146, b: 54, a: 0.16),
            accentRing: RGBAColor(r: 212, g: 146, b: 54, a: 0.05),
            traceHex: "D49236",
            recHex: "C43A1C",
            recGlow: RGBAColor(r: 196, g: 58, b: 28, a: 0.3),
            sparkleHex: "C43A1C",
            edge: RGBAColor(r: 20, g: 24, b: 28, a: 0.14),
            edgeStrong: RGBAColor(r: 20, g: 24, b: 28, a: 0.3),
            detailsBg: RGBAColor(r: 20, g: 24, b: 28, a: 0.04),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.4),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.08)
        ),
        "bone": SchemeTokens(
            key: "bone",
            name: "BONE",
            swatchHex: "9A6A22",
            bgHex: "E8E2D2",
            stripTop: [
                GradientStop(hex: "ECE6D7", location: 0),
                GradientStop(hex: "E5DECC", location: 0.6),
                GradientStop(hex: "DDD5C0", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "E1DAC8", location: 0),
                GradientStop(hex: "E8E2D2", location: 0.55),
                GradientStop(hex: "EFEADC", location: 1),
            ],
            graticule: RGBAColor(r: 154, g: 106, b: 34, a: 0.1),
            inkHex: "2A2520",
            inkFaintHex: "6B5D4F",
            inkSubtleHex: "5C4F42",
            accentHex: "9A6A22",
            accentGlow: RGBAColor(r: 154, g: 106, b: 34, a: 0.14),
            accentRing: RGBAColor(r: 154, g: 106, b: 34, a: 0.05),
            traceHex: "9A6A22",
            recHex: "B53620",
            recGlow: RGBAColor(r: 181, g: 54, b: 32, a: 0.3),
            sparkleHex: "B53620",
            edge: RGBAColor(r: 60, g: 40, b: 20, a: 0.14),
            edgeStrong: RGBAColor(r: 154, g: 106, b: 34, a: 0.38),
            detailsBg: RGBAColor(r: 60, g: 40, b: 20, a: 0.04),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.45),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.08)
        ),
        "paper": SchemeTokens(
            key: "paper",
            name: "PAPER",
            swatchHex: "9A6A22",
            bgHex: "EEE7D6",
            stripTop: [
                GradientStop(hex: "F2ECDB", location: 0),
                GradientStop(hex: "EAE3D0", location: 0.6),
                GradientStop(hex: "E2DBC6", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "E6DFCC", location: 0),
                GradientStop(hex: "EEE7D6", location: 0.55),
                GradientStop(hex: "F4EEDE", location: 1),
            ],
            graticule: RGBAColor(r: 154, g: 106, b: 34, a: 0.1),
            inkHex: "2A2520",
            inkFaintHex: "6B5D4F",
            inkSubtleHex: "5C4F42",
            accentHex: "9A6A22",
            accentGlow: RGBAColor(r: 154, g: 106, b: 34, a: 0.14),
            accentRing: RGBAColor(r: 154, g: 106, b: 34, a: 0.05),
            traceHex: "9A6A22",
            recHex: "B53620",
            recGlow: RGBAColor(r: 181, g: 54, b: 32, a: 0.3),
            sparkleHex: "B53620",
            edge: RGBAColor(r: 60, g: 40, b: 20, a: 0.16),
            edgeStrong: RGBAColor(r: 154, g: 106, b: 34, a: 0.42),
            detailsBg: RGBAColor(r: 60, g: 40, b: 20, a: 0.04),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.45),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.08)
        ),
        "porcelain": SchemeTokens(
            key: "porcelain",
            name: "PORCELAIN",
            swatchHex: "D49236",
            bgHex: "EAEEF1",
            stripTop: [
                GradientStop(hex: "F2F5F7", location: 0),
                GradientStop(hex: "E8ECEF", location: 0.6),
                GradientStop(hex: "DCE0E4", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "E0E4E8", location: 0),
                GradientStop(hex: "EAEEF1", location: 0.55),
                GradientStop(hex: "F0F3F6", location: 1),
            ],
            graticule: RGBAColor(r: 212, g: 146, b: 54, a: 0.08),
            inkHex: "2A2E32",
            inkFaintHex: "5C6168",
            inkSubtleHex: "787D84",
            accentHex: "D49236",
            accentGlow: RGBAColor(r: 212, g: 146, b: 54, a: 0.14),
            accentRing: RGBAColor(r: 212, g: 146, b: 54, a: 0.05),
            traceHex: "D49236",
            recHex: "C43A1C",
            recGlow: RGBAColor(r: 196, g: 58, b: 28, a: 0.28),
            sparkleHex: "C43A1C",
            edge: RGBAColor(r: 20, g: 24, b: 28, a: 0.1),
            edgeStrong: RGBAColor(r: 20, g: 24, b: 28, a: 0.24),
            detailsBg: RGBAColor(r: 20, g: 24, b: 28, a: 0.03),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.55),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.06)
        ),
        "vellum": SchemeTokens(
            key: "vellum",
            name: "VELLUM",
            swatchHex: "9A6A22",
            bgHex: "F4EFE0",
            stripTop: [
                GradientStop(hex: "F8F3E5", location: 0),
                GradientStop(hex: "F0EBDB", location: 0.6),
                GradientStop(hex: "E8E2D0", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "ECE6D6", location: 0),
                GradientStop(hex: "F4EFE0", location: 0.55),
                GradientStop(hex: "F9F4E6", location: 1),
            ],
            graticule: RGBAColor(r: 154, g: 106, b: 34, a: 0.08),
            inkHex: "2A2520",
            inkFaintHex: "6B5D4F",
            inkSubtleHex: "857664",
            accentHex: "9A6A22",
            accentGlow: RGBAColor(r: 154, g: 106, b: 34, a: 0.12),
            accentRing: RGBAColor(r: 154, g: 106, b: 34, a: 0.05),
            traceHex: "9A6A22",
            recHex: "B53620",
            recGlow: RGBAColor(r: 181, g: 54, b: 32, a: 0.28),
            sparkleHex: "B53620",
            edge: RGBAColor(r: 60, g: 40, b: 20, a: 0.12),
            edgeStrong: RGBAColor(r: 154, g: 106, b: 34, a: 0.36),
            detailsBg: RGBAColor(r: 60, g: 40, b: 20, a: 0.03),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.55),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.06)
        ),
        "pearl": SchemeTokens(
            key: "pearl",
            name: "PEARL",
            swatchHex: "D49236",
            bgHex: "F5F8FA",
            stripTop: [
                GradientStop(hex: "FBFCFE", location: 0),
                GradientStop(hex: "F2F5F7", location: 0.6),
                GradientStop(hex: "E5E9ED", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "ECEFF2", location: 0),
                GradientStop(hex: "F5F8FA", location: 0.55),
                GradientStop(hex: "FBFDFE", location: 1),
            ],
            graticule: RGBAColor(r: 212, g: 146, b: 54, a: 0.06),
            inkHex: "2A2E32",
            inkFaintHex: "6E737B",
            inkSubtleHex: "8A8F96",
            accentHex: "D49236",
            accentGlow: RGBAColor(r: 212, g: 146, b: 54, a: 0.12),
            accentRing: RGBAColor(r: 212, g: 146, b: 54, a: 0.04),
            traceHex: "D49236",
            recHex: "C43A1C",
            recGlow: RGBAColor(r: 196, g: 58, b: 28, a: 0.24),
            sparkleHex: "C43A1C",
            edge: RGBAColor(r: 20, g: 24, b: 28, a: 0.08),
            edgeStrong: RGBAColor(r: 20, g: 24, b: 28, a: 0.18),
            detailsBg: RGBAColor(r: 20, g: 24, b: 28, a: 0.02),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.65),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.04)
        ),
        "chiffon": SchemeTokens(
            key: "chiffon",
            name: "CHIFFON",
            swatchHex: "9A6A22",
            bgHex: "FAF5E8",
            stripTop: [
                GradientStop(hex: "FDF8EB", location: 0),
                GradientStop(hex: "F5F0E2", location: 0.6),
                GradientStop(hex: "ECE7D6", location: 1),
            ],
            stripBottom: [
                GradientStop(hex: "F0ECDE", location: 0),
                GradientStop(hex: "F8F3E6", location: 0.55),
                GradientStop(hex: "FDF9EC", location: 1),
            ],
            graticule: RGBAColor(r: 154, g: 106, b: 34, a: 0.06),
            inkHex: "2A2520",
            inkFaintHex: "7B6E60",
            inkSubtleHex: "928576",
            accentHex: "9A6A22",
            accentGlow: RGBAColor(r: 154, g: 106, b: 34, a: 0.1),
            accentRing: RGBAColor(r: 154, g: 106, b: 34, a: 0.04),
            traceHex: "9A6A22",
            recHex: "B53620",
            recGlow: RGBAColor(r: 181, g: 54, b: 32, a: 0.24),
            sparkleHex: "B53620",
            edge: RGBAColor(r: 60, g: 40, b: 20, a: 0.1),
            edgeStrong: RGBAColor(r: 154, g: 106, b: 34, a: 0.32),
            detailsBg: RGBAColor(r: 60, g: 40, b: 20, a: 0.02),
            bezelHighlight: RGBAColor(r: 255, g: 255, b: 255, a: 0.65),
            bezelShadow: RGBAColor(r: 0, g: 0, b: 0, a: 0.04)
        ),
    ]
}
