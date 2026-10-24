// swift-tools-version: 6.0
import PackageDescription

// MyPianoCore depends on Foundation only and builds on Linux as well as macOS,
// so the model, parsers and practice engine can be tested anywhere.
// The other libraries wrap Apple frameworks and compile to empty modules elsewhere.
let package = Package(
    name: "MyPianoKit",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyPianoCore", targets: ["MyPianoCore"]),
        .library(name: "MyPianoMIDI", targets: ["MyPianoMIDI"]),
        .library(name: "MyPianoAudio", targets: ["MyPianoAudio"]),
        .library(name: "MyPianoRendering", targets: ["MyPianoRendering"]),
        .library(name: "MyPianoLibrary", targets: ["MyPianoLibrary"]),
    ],
    targets: [
        .target(name: "MyPianoCore"),
        .target(name: "MyPianoMIDI", dependencies: ["MyPianoCore"]),
        .target(name: "MyPianoAudio", dependencies: ["MyPianoCore"]),
        .target(name: "MyPianoRendering", dependencies: ["MyPianoCore"]),
        .target(name: "MyPianoLibrary", dependencies: ["MyPianoCore"]),
        .testTarget(
            name: "MyPianoCoreTests",
            dependencies: ["MyPianoCore"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
