import Foundation

protocol Node {
  var position: Position { get }
  func string() -> String
}

struct Empty: Node {
  let comment: String
  let leadingSpace: Int
  let position: Position
  
  func string() -> String {
    if comment.isEmpty {
      return ""
    }
    
    return "\(String(repeating: " ", count: leadingSpace))#\(comment)"
  }
}


struct KV: Node {
  let key: String
  var value: String
  let comment: String
  let hasEquals: Bool
  let leadingSpace: Int
  let position: Position
  
  func string() -> String {
    if key.isEmpty {
      return ""
    }
    
    let equals = hasEquals ? " = " : " "
    
    var line = "\(String(repeating: " ", count: leadingSpace))\(key)\(equals)\(value)"
    if !comment.isEmpty {
      line += " #\(comment)"
    }
    
    return line
  }
}

struct Include: Node {
  var comment: String
  var derectives: [String]
  var position: Position
  var matches: [String]
  var files: [String: Config]
  var leadingSpace: Int
  var depth: Int
  var hasEquals: Bool
  
  func string() -> String {
    ""
  }
  
}


class Parser {
  
  let config = Config()
  
  private struct State  {
    let fn: (() throws -> State)?
  }
  
  private var _tokensBuffer = [Token]()
  private var _lexer: Lexer
  
  init(input: String) {
    _lexer = Lexer(input: input)
  }
  
  private func _parseStart() throws -> State {
    guard let tok = _peek()
    else {
      return State(fn: nil)
    }
    
    switch tok.type {
    case .comment, .emptyLine:
      return State(fn: _parseComment)
    case .key:
      return State(fn: _parseKV)
    case .eof:
      return State(fn: nil)
    default:
      throw SSHConfig.Err.unexpected(token: tok)
    }
  }
  
  private func _parseKV() throws -> State {
    guard
      let key = _getToken(),
      var val = _getToken()
    else {
      throw SSHConfig.Err.expectedToken
    }
    var hasEquals = false
    
    if case TokenType.equals = val.type {
      hasEquals = true
      guard let v = _getToken()
      else {
        throw SSHConfig.Err.expectedToken
      }
      val = v
    }
    
    var comment = ""
    var tok = _peek()
    if tok == nil {
      tok = Token(position: Position(line: 1, col: 1), type: .eof, value: "")
    }
    
    if case TokenType.comment = tok!.type, tok!.position.line == val.position.line {
      tok = _getToken()!
      comment = tok!.value
    }
    
    let value = key.value.lowercased()
    
    if value == "match" {
      throw SSHConfig.Err.matchIsUnsupported
    }
    
    if value == "host" {
      let strPatterns = val.value.components(separatedBy: " ").map { String($0) }
      var patterns = [Pattern]()
      for i in strPatterns {
        if i.isEmpty {
          continue
        }
        let pattern = try Pattern(str: i)
        patterns.append(pattern)
      }
      
      let host = Host(patterns: patterns)
      host.eolComment = comment
      host.hasEquals = hasEquals
      
      config.hosts.append(host)
      
      return State(fn: _parseStart)
    }
    
    let lastHost = config.hosts.last
    if value == "include" {
      // todo include
      return State(fn: _parseStart)
    }
    
    let kv = KV(
      key: key.value,
      value: val.value,
      comment: comment,
      hasEquals: hasEquals,
      leadingSpace: key.position.col - 1,
      position: key.position
    )
    lastHost?.nodes.append(kv)
    
    return State(fn: _parseStart)
  }
  
  private func _parseComment() throws -> State {
    guard let comment = _getToken() else {
      throw SSHConfig.Err.emptyPattern
    }
    let lastHost = config.hosts.last
    lastHost?.nodes.append(
      Empty(
        comment: comment.value,
        leadingSpace: comment.position.col - 2,
        position: comment.position
      )
    )
    
    return State(fn: _parseStart)
  }
  
  private func _peek() -> Token? {
    if let token = _tokensBuffer.first {
      return token
    }
    
    _tokensBuffer = _lexer.tokens()
    return _tokensBuffer.first
  }
  
  private func _getToken() -> Token? {
    if let token = _tokensBuffer.first {
      _tokensBuffer.removeFirst()
      return token
    }
    
    _tokensBuffer = _lexer.tokens()
    if let token = _tokensBuffer.first {
      _tokensBuffer.removeFirst()
      return token
    }
    return nil
  }
  
  func parse() throws -> Config {
    var state: State? = State(fn: _parseStart)
    while let s = state {
      state = try s.fn?()
    }
    
    return config
  }
  
}