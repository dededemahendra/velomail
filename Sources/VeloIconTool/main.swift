import Foundation
import VeloIcon

// Writes the .iconset that `make-app.sh` hands to `iconutil`.
//
// A directory argument keeps it out of the way of the source tree: the build
// script points it at a temporary directory and cleans up afterwards.
let target = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("AppIcon.iconset")

do {
    try AppIconRenderer.writeIconset(to: target)
    print("wrote \(AppIconRenderer.representations.count) images to \(target.path)")
} catch {
    FileHandle.standardError.write(Data("velo-icon: \(error)\n".utf8))
    exit(1)
}
