
/// Lightweight logging in swift, https://github.com/SwiftyBeaver/SwiftyBeaver
import SwiftyBeaver

// setup logging
let LOG = SwiftyBeaver.self
let console = ConsoleDestination()
console.dateFormat = "HH:mm:ss.SSS"
console.colored = false
LOG.addDestination(console)

LOG.info("Start")

// keep track of response handler running async
let LATCH = CountdownLatch()

// run response handler async in their own queue
let IMAP_QUEUE = dispatch_queue_create("my.imap-queue", DISPATCH_QUEUE_SERIAL)

//TODO take config path from command line
let plistPath = "/Users/prenagha/Dev/imap-tools/config.plist"
let CONFIG = Config(path: plistPath)

// Load up a map of the servers, run folder list to initiate connection and
// check that things are ok
var servers = [String: IMAPServer]()
for serverName in CONFIG.getServers() {
  let server = IMAPServer(name: serverName)
  server.folderList()
  servers[serverName] = server
}

// Perform the delete old items action
for server in servers.values {
  let (deleteOlderThanDays, deleteFromFolder) = CONFIG.getDeleteOlderThan(server.name)
  if deleteOlderThanDays > 0 {
    LOG.info("\(server.name) delete older than \(deleteOlderThanDays) days from \(deleteFromFolder)")
    server.deleteOlderThan(deleteFromFolder, olderThanDays: Int(deleteOlderThanDays))
  }
}

// block main thread until all our tasks are complete or 10s has passed
if LATCH.wait(60) {
  LOG.info("All operations complete")
} else {
  LOG.error("ERROR operations did not complete")
}

LOG.info("End")
LOG.flush(10)
