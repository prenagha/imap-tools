import Foundation

/// An IMAP server
class IMAPServer {

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

  func messagesInFolder(folder: String) {
    let fetchMessages = session.fetchMessagesOperationWithFolder(folder,
      requestKind: .InternalDate,
      uids: MCOIndexSet.init(range: MCORange(location: 1, length: UInt64.max)))
    LATCH.add()
    fetchMessages.start { (err, messages, _) in
      if let e = err {
        LOG.error("\(self.name) \(folder) fetch messages error: \(e)")
      } else {
        LOG.info("Found \(messages!.count) messages in \(self.name) \(folder)")
        for m in messages! {
          let message = m as! MCOIMAPMessage
          LOG.verbose("  \(message.uid) \(message.flags)")
        }
      }
      LATCH.remove()
    }
  }
}