import Foundation

/// Helpful wrapper around accounts.plist
class Accounts {

  let props: NSDictionary

  init(path: String) {
    if let dict = NSDictionary(contentsOfFile: path) {
      props = dict
    } else {
      props = NSDictionary()
      log.error("Unable to create dictionary from plist \(path)")
    }
  }

  private func prop(account: String, key: String) -> AnyObject? {
    if let a = props.objectForKey(account) {
      if let p = a.objectForKey(key) {
        return p
      } else {
        log.error("Key \(key) not found in \(account) in plist")
        return nil
      }
    } else {
      log.error("Account \(account) not found in plist")
      return nil
    }
  }

  func getServer(account: String) -> String {
    if let v = prop(account, key: "Server") {
      return v as! String
    } else {
      return ""
    }
  }

  func getPort(account: String) -> UInt32 {
    if let v = prop(account, key: "Port") {
      let n = v as! NSNumber
      return UInt32(n.doubleValue)
    } else {
      return 993
    }
  }

  func getUsername(account: String) -> String {
    if let v = prop(account, key: "Username") {
      return v as! String
    } else {
      return ""
    }
  }

  func getPassword(account: String) -> String {
    if let v = prop(account, key: "Password") {
      return v as! String
    } else {
      return ""
    }
  }

}