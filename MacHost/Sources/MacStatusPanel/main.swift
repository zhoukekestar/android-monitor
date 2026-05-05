import Foundation
import Network

let port = UInt16(CommandLine.arguments.dropFirst().first ?? "") ?? 38889
let server = StatusPanelServer(port: port)
try server.start()
RunLoop.current.run()
