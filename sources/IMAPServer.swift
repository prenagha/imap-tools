import Foundation

/// An IMAP server
class IMAPServer {
  // Mail Core range for "all" possible messages
  private static let RANGE_ALL = MCOIndexSet(range: MCORange(location: 1, length: UInt64.max))
  // How long to wait in seconds for IMAP action to complete
  private static let WAITS = 5 * 60
  // run response handler async in their own queue
  private static let IMAP_QUEUE = dispatch_queue_create("com.renaghan.imap-tools", DISPATCH_QUEUE_CONCURRENT)

  let name: String
  let session: MCOIMAPSession

  init(name: String, hostname: String, port: Int, username: String, password: String) {
    self.name = name
    session = MCOIMAPSession()
    session.dispatchQueue = IMAPServer.IMAP_QUEUE
    session.hostname = hostname
    session.port = UInt32(port)
    session.username = username
    session.password = password
    session.connectionType = MCOConnectionType.TLS
    if session.port == 143 {
      session.connectionType = MCOConnectionType.Clear
    }
  }

  /**
   Get a list of folders on this server and output verbose to log
   */
  func folderList() {
    let latch = CountdownLatch()
    latch.add()
    LOG.verbose("Folder list \(name)...")
    session.fetchAllFoldersOperation()
      .start { (err, folders) in
      if let e = err {
        LOG.error("\(self.name) folder list error: \(e)")
      } else {
        LOG.info("Found \(folders!.count) folders in \(self.name)")
        for f in folders! {
          let folder = f as! MCOIMAPFolder
          LOG.verbose("  \(folder.path)")
        }
      }
      latch.remove()
    }
    if !latch.wait(IMAPServer.WAITS) {
      LOG.error("Folder list in \(name) timeout")
    }
  }

  /**
   How many messages are in a folder

   - parameter folder: to count messages

   - returns: count of messages in that folder
   */
  func countMessages(folder: String) -> Int {
    let latch = CountdownLatch()
    latch.add()

    var cnt = 0
    LOG.info("Count messages in \(name)/\(folder)...")
    session.fetchMessagesOperationWithFolder(folder, requestKind: .Uid, uids: IMAPServer.RANGE_ALL)
      .start { (err, msgs, _) in
        if let e = err {
          LOG.error("\(self.name)/\(folder) count messages error: \(e)")
        } else if let messages = msgs {
          cnt = messages.count
        } else {
          LOG.error("\(self.name)/\(folder) count messages returned nothing")
        }
        latch.remove()
    }
    if latch.wait(IMAPServer.WAITS) {
      LOG.info("Count \(cnt) messages in \(self.name)/\(folder)")
      return cnt
    } else {
      LOG.error("Count messages in \(self.name)/\(folder) timeout")
      return 0
    }

  }

  /**
   Find messages in a folder that are older than the specified days.
   Uses received date to determine age.

   - parameter folder:        look in this folder
   - parameter olderThanDays: received date older than this, must be > 0

   - returns: MCOIndexSet containing UID of all messages found
   */
  func findOldMessages(folder: String, olderThanDays: Int) -> MCOIndexSet {
    if olderThanDays <= 0 {
      return MCOIndexSet()
    }

    let now = NSDate()
    let cal = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
    let days: NSCalendarUnit = [.Day]
    let kind: MCOIMAPMessagesRequestKind = [.Uid, .InternalDate]

    let latch = CountdownLatch()
    latch.add()

    LOG.info("Finding old messages in \(name)/\(folder) older than \(olderThanDays)...")
    let found = MCOIndexSet()
    session.fetchMessagesOperationWithFolder(folder, requestKind: kind, uids: IMAPServer.RANGE_ALL)
      .start { (err, msgs, _) in
      if let e = err {
        LOG.error("\(self.name)/\(folder) find old messages error: \(e)")
      } else if let messages = msgs {
        LOG.info("\(self.name)/\(folder) \(messages.count) total messages")
        for m in messages {
          let message = m as! MCOIMAPMessage
          let components =
          cal!.components(days, fromDate: message.header.receivedDate, toDate: now, options: [])
          let ageDays = components.day
          if ageDays >= olderThanDays {
            LOG.verbose("  \(message.uid) \(message.header.receivedDate) \(ageDays)")
            found.addIndex(UInt64(message.uid))
          }
        }
      } else {
        LOG.error("\(self.name)/\(folder) find old messages returned nothing")
      }
      latch.remove()
    }
    if latch.wait(IMAPServer.WAITS) {
      LOG.info("Found \(found.size) old messages in \(self.name)/\(folder) older than \(olderThanDays)")
      return found
    } else {
      LOG.error("Find old messages in \(self.name)/\(folder) timeout")
      return MCOIndexSet()
    }
  }

  /**
   Mark (set deleted flag) a set of messages (by UID) as deleted

   - parameter folder:   containing messages
   - parameter messages: to mark as deleted
   */
  func markDeleted(folder: String, messages: MCOIndexSet) {
    if messages.size == 0 {
      return
    }

    let latch = CountdownLatch()
    latch.add()

    LOG.info("Mark \(messages.size) deleted in \(name)/\(folder)...")
    let deletedFlag: MCOMessageFlag = [.Deleted]
    session.storeFlagsOperationWithFolder(folder, uids: messages, kind: .Set, flags: deletedFlag)
      .start { (err) in
        if let e = err {
          LOG.error("\(self.name)/\(folder) mark deleted error: \(e)")
        } else {
          LOG.info("\(self.name)/\(folder) mark deleted success")
        }
        latch.remove()
    }
    if !latch.wait(IMAPServer.WAITS) {
      LOG.error("Mark deleted in \(self.name)/\(folder) timeout")
    }
  }

  /**
   Expunge (remove all deleted items) from a folder

   - parameter folder: to expunge
   */
  func expunge(folder: String) {
    let latch = CountdownLatch()
    latch.add()

    LOG.info("Expunge \(name)/\(folder)...")
    session.expungeOperation(folder)
      .start { (err) in
        if let e = err {
          LOG.error("\(self.name)/\(folder) expunge error: \(e)")
        } else {
          LOG.info("\(self.name)/\(folder) expunge success")
        }
        latch.remove()
    }
    if !latch.wait(IMAPServer.WAITS) {
      LOG.error("Expunge \(self.name)/\(folder) timeout")
    }
  }


  /**
   Get a full messages from IMAP server

   - parameter folder:    to read messages from
   - parameter uid:       message id to read

   - returns: full data of message
   */
  func readFullMessage(folder: String, uid: Int) -> NSData {
    let latch = CountdownLatch()
    latch.add()

    var data = NSData()
    LOG.info("Read \(uid) from \(name)/\(folder)...")
    session.fetchMessageOperationWithFolder(folder, uid: UInt32(uid))
      .start { (err, d) in
        if let e = err {
          LOG.error("\(self.name)/\(folder) read message error: \(e)")
        } else if let dat = d {
          data = dat
        } else {
          LOG.error("\(self.name)/\(folder) read message returned nothing")
        }
        latch.remove()
    }
    if latch.wait(IMAPServer.WAITS) {
      LOG.info("Read \(uid) message \(data.length) bytes from \(self.name)/\(folder)")
      return data
    } else {
      LOG.error("Read \(uid) message in \(self.name)/\(folder) timeout")
      return NSData()
    }
  }

  /**
   Add message to folder

   - parameter folder:      to add message to
   - parameter fullMessage: to add to folder
   */
  func addMessage(folder: String, fullMessage: NSData) {
    let latch = CountdownLatch()
    latch.add()

    LOG.info("Add message to \(name)/\(folder)...")
    session.appendMessageOperationWithFolder(folder, messageData: fullMessage, flags: [.Seen])
      .start { (err, uid) in
        if let e = err {
          LOG.error("\(self.name)/\(folder) add message error: \(e)")
        } else {
          LOG.info("\(self.name)/\(folder) added message \(uid)")
        }
        latch.remove()
    }
    if !latch.wait(IMAPServer.WAITS) {
      LOG.error("Add message \(self.name)/\(folder) timeout")
    }
  }
}