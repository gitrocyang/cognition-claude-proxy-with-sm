// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevinProxyManager",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DevinProxyManager", targets: ["DevinProxyManager"])],
    targets: [
        .executableTarget(name: "DevinProxyManager"),
        .testTarget(name: "DevinProxyManagerTests", dependencies: ["DevinProxyManager"])
    ]
)
