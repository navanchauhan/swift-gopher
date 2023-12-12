//
//  fileTypes.swift
//
//
//  Created by Navan Chauhan on 12/3/23.
//

import Foundation

enum ResponseType {
  case string(String)
  case data(Data)
}

enum gopherFileType {
  case text
  case directory
  case nameserver
  case error
  case binhex
  case bindos
  case uuencoded
  case indexSearch
  case telnet
  case binary
  case redundantServer
  case tn3270Session
  case gif
  case image
  case bitmap
  case movie
  case sound
  case doc
  case html
  case message
  case png
  case rtf
  case wavfile
  case pdf
  case xml
}

func getFileType(fileExtension: String) -> gopherFileType {
  switch fileExtension {
  case "txt":
    return .text
  case "md":
    return .text
  case "html":
    return .html
  case "pdf":
    return .pdf
  case "png":
    return .png
  case "gif":
    return .gif
  case "jpg":
    return .image
  case "jpeg":
    return .image
  case "mp3":
    return .sound
  case "wav":
    return .wavfile
  case "mp4":
    return .movie
  case "mov":
    return .movie
  case "avi":
    return .movie
  case "rtf":
    return .rtf
  case "xml":
    return .xml
  default:
    return .binary
  }
}

func fileTypeToGopherItem(fileType: gopherFileType) -> String {
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
  case .indexSearch:
    return "7"
  case .telnet:
    return "8"
  case .binary:
    return "9"
  case .redundantServer:
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
  case .message:
    return "i"
  case .png:
    return "p"
  case .rtf:
    return "t"
  case .wavfile:
    return "w"
  case .pdf:
    return "P"
  case .xml:
    return "x"
  }
}
