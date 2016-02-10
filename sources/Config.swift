import Foundation

/// Helpful wrapper around config.plist
class Config {

  let props: NSDictionary

  init(path: String) {
    if let dict = NSDictionary(contentsOfFile: path) {
      props = dict
    } else {
      props = NSDictionary()
      LOG.error("Unable to create dictionary from plist \(path)")
    }
  }

  func getServers() -> [String] {
    var servers :[String] = []
    let keys = props.allKeys
    for key in keys {
      let server = key as! String
      servers.append(server)
    }
    return servers
  }

  private func accountProp(account: String, key: String) -> AnyObject? {
    if let a = props.objectForKey(account) {
      if let p = a.objectForKey(key) {
        return p
      } else {
        LOG.warning("Key \(key) not found in \(account) in plist")
        return nil
      }
    } else {
      LOG.error("Account \(account) not found in plist")
      return nil
    }
  }

  func getServer(account: String) -> String {
    if let v = accountProp(account, key: "Server") {
      return v as! String
    } else {
      return ""
    }
  }

  func getPort(account: String) -> UInt32 {
    if let v = accountProp(account, key: "Port") {
      let n = v as! NSNumber
      return UInt32(n.doubleValue)
    } else {
      return 993
    }
  }

  func getUsername(account: String) -> String {
    if let v = accountProp(account, key: "Username") {
      return v as! String
    } else {
      return ""
    }
  }

  func getPassword(account: String) -> String {
    if let v = accountProp(account, key: "Password") {
      return v as! String
    } else {
      return ""
    }
  }

  func getDeleteOlderThan(account: String) -> (Int, String) {
    if let v = accountProp(account, key: "DeleteOlderThanDays") {
      let n = v as! NSNumber
      if let f = accountProp(account, key: "DeleteOlderThanFolder") {
        return (Int(n.doubleValue), f as! String)
      }
    }
    return (0, "")
  }

  func getArchiveOlderThan(account: String) -> ([String], String, String, Int) {
    if let ff=accountProp(account, key: "ArchiveFromFolders")
    , let ts=accountProp(account, key: "ArchiveToServer")
    , let tf=accountProp(account, key: "ArchiveToFolder")
    , let d=accountProp(account, key: "ArchiveOlderThanDays") {
      return ((ff as! String).split(","), ts as! String, tf as! String, Int((d as! NSNumber).doubleValue))
    } else {
      return ([], "", "", 0)
    }
  }

}