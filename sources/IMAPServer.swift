import Foundation

/// An IMAP server
class IMAPServer {
  private static let RANGE_ALL = MCOIndexSet(range: MCORange(location: 1, length: UInt64.max))

  let name: String
  let session: MCOIMAPSession

  init(name: String) {
    self.name = name
    session = MCOIMAPSession()
    session.dispatchQueue = IMAP_QUEUE
    session.hostname = CONFIG.getServer(name)
    session.port = CONFIG.getPort(name)
    session.username = CONFIG.getUsername(name)
    session.password = CONFIG.getPassword(name)
    if session.port == 143 {
      session.connectionType = MCOConnectionType.Clear
    } else {
      session.connectionType = MCOConnectionType.TLS
    }
  }

  func folderList() {
    let fetchFolders = session.fetchAllFoldersOperation()
    LATCH.add()
    fetchFolders.start { (err, folders) in
      if let e = err {
        LOG.error("\(self.name) folder list error: \(e)")
      } else {
        LOG.info("Found \(folders!.count) folders in \(self.name)")
        for f in folders! {
          let folder = f as! MCOIMAPFolder
          LOG.verbose("  \(folder.path)")
        }
      }
      LATCH.remove()
    }
  }

  func copyTo(destServer: IMAPServer, destFolder: String, olderThanDays: Int) {
    //appendMessageOperationWithFolder:messageData:flags:
  }

  func deleteOlderThan(folder: String, olderThanDays: Int) {
    if olderThanDays <= 0 {
      return
    }
    let now = NSDate()
    let cal = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)
    let days: NSCalendarUnit = [.Day]
    let kind: MCOIMAPMessagesRequestKind = [.Uid, .InternalDate]
    let willDelete = MCOIndexSet()
    let fetchMessages = session.fetchMessagesOperationWithFolder(folder,
      requestKind: kind, uids: IMAPServer.RANGE_ALL)
    LATCH.add()
    fetchMessages.start { (err, messages, _) in
      if let e = err {
        LOG.error("\(self.name) \(folder) fetch messages error: \(e)")
      } else {
        LOG.info("Found \(messages!.count) messages in \(self.name) \(folder)")
        for m in messages! {
          let message = m as! MCOIMAPMessage
          let components =
            cal!.components(days, fromDate: message.header.receivedDate, toDate: now, options: [])
          let ageDays = components.day
          if ageDays >= olderThanDays {
            willDelete.addIndex(UInt64(message.uid))
            LOG.verbose("  \(message.uid) \(message.header.receivedDate) \(ageDays)")
          }
        }
      }

      LOG.info("Found \(willDelete.count()) messages to delete")
      if willDelete.count() == 0 {
        LATCH.remove()
        return
      }

      let flags: MCOMessageFlag = [.Deleted]
      let setFlags = self.session.storeFlagsOperationWithFolder(folder, uids: willDelete, kind: .Set, flags: flags)
      LATCH.add()
      setFlags.start{ err in
        if let e = err {
          LOG.error("\(self.name) \(folder) set delete flag error: \(e)")
        } else {
          LOG.info("\(self.name) \(folder) set delete flag success")

          let expunge = self.session.expungeOperation(folder)
          LATCH.add()
          expunge.start{ err in
            if let e = err {
              LOG.error("\(self.name) \(folder) expunge error: \(e)")
            } else {
              LOG.info("\(self.name) \(folder) expunge success")
            }
            LATCH.remove()
          }

        }
        LATCH.remove()
      }

      LATCH.remove()
    }

  }
}