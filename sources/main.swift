
/// Lightweight logging in swift, https://github.com/SwiftyBeaver/SwiftyBeaver
import SwiftyBeaver

// setup logging
let LOG = SwiftyBeaver.self
let console = ConsoleDestination()
console.dateFormat = "HH:mm:ss.SSS"
console.colored = false
LOG.addDestination(console)

LOG.info("Start")

//TODO take config path from command line
let plistPath = "/Users/prenagha/Dev/imap-tools/config.plist"
let CONFIG = Config(path: plistPath)

// Load up a map of the servers, run folder list to initiate connection and
// check that things are ok by listing folders out
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
    let deleteMe = server.findOldMessages(deleteFromFolder, olderThanDays: deleteOlderThanDays)
    if deleteMe.size > 0 {
      server.markDeleted(deleteFromFolder, messages: deleteMe)
      server.expunge(deleteFromFolder)
    }
  }
}

// Perform the archive move action
sloop: for sourceServer in servers.values {
  let (archiveFromFolders, archiveToServer, archiveToFolder, archiveOlderThanDays)
    = CONFIG.getArchiveOlderThan(sourceServer.name)
  if archiveOlderThanDays > 0 && archiveFromFolders.count > 0 {
    let destServer = servers[archiveToServer]!

    for archiveFromFolderLong in archiveFromFolders {
      let archiveFromFolder = archiveFromFolderLong.trimmed()
      
      LOG.info("Archiving from \(sourceServer.name)/\(archiveFromFolder) to \(destServer.name)/\(archiveToFolder) older than \(archiveOlderThanDays) days")

      // find messages in the source folder that should be copied
      let archiveMe = sourceServer.findOldMessages(archiveFromFolder, olderThanDays: archiveOlderThanDays)

      if archiveMe.size > 0 {
        LOG.verbose("Found \(archiveMe.size) messages to archive")

        // count of messages in the destination folder before the copy
        let countBeforeCopy = destServer.countMessages(archiveToFolder)

        for uid in archiveMe.nsIndexSet() {
          // read full message from the source server
          let fullMessage = sourceServer.readFullMessage(archiveFromFolder, uid: uid)
          if fullMessage.length == 0 {
            LOG.error("Message read failed, empty \(uid)")
            break sloop
          }

          // add the message to the destination server/folder
          destServer.addMessage(archiveToFolder, fullMessage: fullMessage)
        }

        // count the messages in the destination folder after the copy
        let countAfterCopy = destServer.countMessages(archiveToFolder)

        // make sure the counts add up, proving the copy worked
        if countAfterCopy >= (countBeforeCopy + archiveMe.size) {
          LOG.info("Copy check success before=\(countBeforeCopy) after=\(countAfterCopy) count=\(archiveMe.size)")
          // mark deleted in the source folder
          sourceServer.markDeleted(archiveFromFolder, messages: archiveMe)
          // expunge the source folder
          sourceServer.expunge(archiveFromFolder)
        } else {
          LOG.error("Copy check failed before=\(countBeforeCopy) after=\(countAfterCopy) count=\(archiveMe.size)")
          break sloop
        }
      }
    }
  }
}

LOG.info("End")
LOG.flush(10)
