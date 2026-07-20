import AuthCompanionCore
import Darwin
import Foundation

let result = AuthCompanionApplication.live(effectiveUserID: geteuid()).run(CommandLine.arguments)
if !result.stdout.isEmpty {
  FileHandle.standardOutput.write(Data(result.stdout.utf8))
}
if !result.stderr.isEmpty {
  FileHandle.standardError.write(Data(result.stderr.utf8))
}
exit(result.exitStatus)
