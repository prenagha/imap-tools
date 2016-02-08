
/// Lightweight logging in swift, https://github.com/SwiftyBeaver/SwiftyBeaver
import SwiftyBeaver

// setup logging
let log = SwiftyBeaver.self
let console = ConsoleDestination()
console.dateFormat = "HH:mm:ss.SSS"
console.colored = false
log.addDestination(console)

log.info("Start")

// keep track of response handler running async
let latch = CountdownLatch()

// run response handler async in their own queue
let queue = dispatch_queue_create("my.imap-queue", DISPATCH_QUEUE_CONCURRENT)

var session = MCOIMAPSession()
session.dispatchQueue = queue

let plistPath = "/Users/prenagha/Dev/imap-tools/accounts.plist"
let accounts = Accounts(path: plistPath)
let accountName = "Work"

session.hostname = accounts.getServer(accountName)
session.port = accounts.getPort(accountName)
session.username = accounts.getUsername(accountName)
session.password = accounts.getPassword(accountName)
session.connectionType = MCOConnectionType.TLS

let uidSet = MCOIndexSet(range: MCORange(location: 1, length: UINT64_MAX))
let fetchOp = session.fetchMessagesByUIDOperationWithFolder(
  "Trash", requestKind: MCOIMAPMessagesRequestKind.Headers, uids: uidSet)

log.verbose("fetch start")
latch.add()
fetchOp.start { (err, msgs, vanished) in
  if let e = err {
    log.error("fetch error: \(e)")
  } else {
    log.info("fetch success \(msgs!.count) messages")
  }
  latch.remove()
}
log.verbose("fetch end")


// block main thread until all our tasks are complete or 10s has passed
if latch.wait(10) {
  log.info("All operations complete")
} else {
  log.error("ERROR operations did not complete")
}

log.info("End")
log.flush(10)
