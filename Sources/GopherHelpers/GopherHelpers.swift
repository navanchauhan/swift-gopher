//
//  File.swift
//
//
//  Created by Navan Chauhan on 12/16/23.
//

import Foundation
import NIOCore

/*

 From Wikipedia

 Canonical types
 0    Text file
 1    Gopher submenu
 2    CCSO Nameserver
 3    Error code returned by a Gopher server to indicate failure
 4    BinHex-encoded file (primarily for Macintosh computers)
 5    DOS file
 6    uuencoded file
 7    Gopher full-text search
 8    Telnet
 9    Binary file
 +    Mirror or alternate server (for load balancing or in case of primary server downtime)
 g    GIF file
 I    Image file
 T    Telnet 3270
 gopher+ types
 :    Bitmap image
 ;    Movie file
 <    Sound file
 Non-canonical types
 d    Doc. Seen used alongside PDF's and .DOC's
 h    HTML file
 i    Informational message, widely used.[25]
 p    image file "(especially the png format)"
 r    document rtf file "rich text Format")
 s    Sound file (especially the WAV format)
 P    document pdf file "Portable Document Format")
 X    document xml file "eXtensive Markup Language" )
 */

public enum gopherItemType {
  case text
  case directory
  case nameserver
  case error
  case binhex
  case bindos
  case uuencoded
  case search
  case telnet
  case binary
  case mirror
  case gif
  case image
  case tn3270Session
  case bitmap
  case movie
  case sound
  case doc
  case html
  case info
}

public struct gopherItem {

  public var rawLine: String
  public var rawData: ByteBuffer?
  public var message: String = ""
  public var parsedItemType: gopherItemType = .info
  public var host: String = "error.host"
  public var port: Int = 1
  public var selector: String = ""
  public var valid: Bool = true

  public init(rawLine: String) {
    self.rawLine = rawLine
  }
}

public func getGopherFileType(item: String) -> gopherItemType {
  switch item {
  case "0":
    return .text
  case "1":
    return .directory
  case "2":
    return .nameserver
  case "3":
    return .error
  case "4":
    return .binhex
  case "5":
    return .bindos
  case "6":
    return .uuencoded
  case "7":
    return .search
  case "8":
    return .telnet
  case "9":
    return .binary
  case "+":
    return .mirror
  case "g":
    return .gif
  case "I":
    return .image
  case "T":
    return .tn3270Session
  case ":":
    return .bitmap
  case ";":
    return .movie
  case "<":
    return .sound
  case "d":
    return .doc
  case "h":
    return .html
  case "i":
    return .info
  case "p":
    return .image
  case "r":
    return .doc
  case "s":
    return .doc
  case "P":
    return .doc
  case "X":
    return .doc
  default:
    return .info
  }
}

public func getFileType(fileExtension: String) -> gopherItemType {
  switch fileExtension {
  case "txt":
    return .text
  case "md":
    return .text
  case "html":
    return .html
  case "pdf":
    return .doc
  case "png":
    return .image
  case "gif":
    return .gif
  case "jpg":
    return .image
  case "jpeg":
    return .image
  case "mp3":
    return .sound
  case "wav":
    return .sound
  case "mp4":
    return .movie
  case "mov":
    return .movie
  case "avi":
    return .movie
  case "rtf":
    return .doc
  case "xml":
    return .doc
  default:
    return .binary
  }
}

public func fileTypeToGopherItem(fileType: gopherItemType) -> String {
  switch fileType {
  case .text:
    return "0"
  case .directory:
    return "1"
  case .nameserver:
    return "2"
  case .error:
    return "3"
  case .binhex:
    return "4"
  case .bindos:
    return "5"
  case .uuencoded:
    return "6"
  case .search:
    return "7"
  case .telnet:
    return "8"
  case .binary:
    return "9"
  case .mirror:
    return "+"
  case .tn3270Session:
    return "T"
  case .gif:
    return "g"
  case .image:
    return "I"
  case .bitmap:
    return "b"
  case .movie:
    return "M"
  case .sound:
    return "s"
  case .doc:
    return "d"
  case .html:
    return "h"
  case .info:
    return "i"
  //  case .png:
  //    return "p"
  //  case .rtf:
  //    return "t"
  //  case .wavfile:
  //    return "w"
  //  case .pdf:
  //    return "P"
  //  case .xml:
  //    return "x"
  }
}

public func itemToImageType(_ item: gopherItem) -> String {
  switch item.parsedItemType {
  case .text:
    return "doc.plaintext"
  case .directory:
    return "folder"
  case .error:
    return "exclamationmark.triangle"
  case .gif:
    return "photo.stack"
  case .image:
    return "photo"
  case .doc:
    return "doc.richtext"
  case .sound:
    return "music.note"
  case .bitmap:
    return "photo"
  case .html:
    return "globe"
  case .movie:
    return "videoprojector"
  default:
    return "questionmark.square.dashed"
  }
}
