// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [.library(name: "MediaForgeCore", targets: ["MediaForgeCore"])]
var targets: [Target] = [
    .target(name: "MediaForgeCore"),
    .testTarget(name: "MediaForgeCoreTests", dependencies: ["MediaForgeCore"])
]
#if os(macOS)
products.append(.executable(name: "MediaForge", targets: ["MediaForge"]))
targets.append(.executableTarget(name: "MediaForge", dependencies: ["MediaForgeCore"], path: "Sources/MediaForgeApp"))
targets.append(.testTarget(name: "MediaForgeAppTests", dependencies: ["MediaForge", "MediaForgeCore"]))
#endif
let package = Package(name: "MediaForge", platforms: [.macOS(.v14)], products: products, targets: targets, swiftLanguageModes: [.v6])
