// swift-tools-version: 6.0
import PackageDescription

// PianissimacCore depends on Foundation only and builds on Linux as well as macOS,
// so the model, parsers and practice engine can be tested anywhere.
// The other libraries wrap Apple frameworks and compile to empty modules elsewhere.
let package = Package(
    name: "PianissimacKit",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PianissimacCore", targets: ["PianissimacCore"]),
        .library(name: "PianissimacMIDI", targets: ["PianissimacMIDI"]),
        .library(name: "PianissimacAudio", targets: ["PianissimacAudio"]),
        .library(name: "PianissimacRendering", targets: ["PianissimacRendering"]),
        .library(name: "PianissimacLibrary", targets: ["PianissimacLibrary"]),
    ],
    targets: [
        .target(name: "PianissimacCore"),
        .target(name: "PianissimacMIDI", dependencies: ["PianissimacCore"]),
        .target(name: "PianissimacAudio", dependencies: ["PianissimacCore"]),
        .target(name: "PianissimacRendering", dependencies: ["PianissimacCore"]),
        .target(name: "PianissimacLibrary", dependencies: ["PianissimacCore"]),
        .testTarget(
            name: "PianissimacCoreTests",
            dependencies: ["PianissimacCore"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
