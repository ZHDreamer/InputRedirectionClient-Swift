#!/usr/bin/env swift
import Foundation
import GameController

// Usage: swift scripts/controller-metadata.swift [--wait seconds] > controllers.json
let usage = """
    Usage: swift scripts/controller-metadata.swift [--wait seconds]

    Print productCategory, vendorName, buttons, and sticks as JSON.
    Waits 3 seconds by default for macOS to enumerate controllers (range: 0–60).
    Connect controllers through Bluetooth or USB before running this script.
    """
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}
var waitSeconds = 3.0
if !arguments.isEmpty {
    guard arguments.count == 2, arguments[0] == "--wait",
        let seconds = Double(arguments[1]), seconds.isFinite, (0...60).contains(seconds)
    else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
    waitSeconds = seconds
}

func optional(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }

func metadata(_ element: GCControllerElement) -> [String: Any] {
    [
        "aliases": element.aliases.sorted(),
        "localizedName": optional(element.localizedName),
        "sfSymbolsName": optional(element.sfSymbolsName),
    ]
}

func controllerMetadata(_ controller: GCController) -> [String: Any] {
    let profile = controller.physicalInputProfile
    return [
        "productCategory": controller.productCategory,
        "vendorName": optional(controller.vendorName),
        "buttons": profile.buttons.mapValues { metadata($0) },
        "sticks": profile.dpads.mapValues { metadata($0) },
    ]
}

GCController.shouldMonitorBackgroundEvents = true
// Initialize enumeration before giving macOS time to deliver connection events.
_ = GCController.controllers()
if waitSeconds > 0 {
    let timer = Timer.scheduledTimer(withTimeInterval: waitSeconds, repeats: false) { _ in }
    RunLoop.main.run(until: Date().addingTimeInterval(waitSeconds))
    timer.invalidate()
}
let controllers = GCController.controllers()
let report = controllers.map(controllerMetadata)
do {
    let json = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data("\n".utf8))
    if controllers.isEmpty {
        FileHandle.standardError.write(
            Data("No controllers detected. Check the connection or retry with --wait 10.\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("Unable to encode controller metadata: \(error)\n".utf8))
    exit(1)
}
