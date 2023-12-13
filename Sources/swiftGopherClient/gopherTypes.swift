//
//  gopherTypes.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation

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

enum gopherItemType {
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

func getGopherFileType(item: String) -> gopherItemType {
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
