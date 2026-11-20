#pragma once
#include <charconv>
#include <cmath>
#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
#include <variant>
#include <vector>

namespace sd::mcp {
constexpr size_t kFrameBytes = 256 * 1024;
// Private IPC codec. Bounds apply while decoding, before any domain dispatch.
struct Json {
  using Object = std::map<std::string, Json>;
  using Array = std::vector<Json>;
  std::variant<std::nullptr_t, bool, int64_t, double, std::string, Object, Array> value;
  Json() : value(nullptr) {}
  Json(std::nullptr_t) : value(nullptr) {}
  Json(bool v) : value(v) {}
  Json(int64_t v) : value(v) {}
  Json(int v) : value(static_cast<int64_t>(v)) {}
  Json(double v) : value(v) {}
  Json(std::string v) : value(std::move(v)) {}
  Json(const char* v) : value(std::string(v)) {}
  Json(Object v) : value(std::move(v)) {}
  Json(Array v) : value(std::move(v)) {}
  const Object& object() const { return std::get<Object>(value); }
  const std::string& string() const { return std::get<std::string>(value); }
  int64_t integer() const { return std::get<int64_t>(value); }
  const Json& at(const std::string& key) const { return object().at(key); }
};
[[noreturn]] inline void InvalidJson() { throw std::runtime_error("MCP_PROTOCOL"); }
inline bool ValidUtf8(const std::string& text) {
  size_t i = 0;
  while (i < text.size()) {
    const auto c = static_cast<uint8_t>(text[i++]);
    if (c < 0x80) continue;
    uint32_t cp = 0, minimum = 0; size_t n = 0;
    if (c >= 0xc2 && c <= 0xdf) { cp = c & 31; minimum = 0x80; n = 1; }
    else if (c >= 0xe0 && c <= 0xef) { cp = c & 15; minimum = 0x800; n = 2; }
    else if (c >= 0xf0 && c <= 0xf4) { cp = c & 7; minimum = 0x10000; n = 3; }
    else return false;
    if (n > text.size() - i) return false;
    while (n--) { const auto d = static_cast<uint8_t>(text[i++]); if ((d & 0xc0) != 0x80) return false; cp = (cp << 6) | (d & 63); }
    if (cp < minimum || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) return false;
  }
  return true;
}
class JsonReader {
 public:
  explicit JsonReader(const std::string& text) : text_(text) {}
  Json read() {
    if (text_.size() >= kFrameBytes || !ValidUtf8(text_)) InvalidJson();
    auto result = item(0); space(); if (position_ != text_.size()) InvalidJson(); return result;
  }
 private:
  const std::string& text_; size_t position_ = 0;
  void space() { while (position_ < text_.size() && (text_[position_] == ' ' || text_[position_] == '\t' || text_[position_] == '\r' || text_[position_] == '\n')) ++position_; }
  char take() { if (position_ == text_.size()) InvalidJson(); return text_[position_++]; }
  bool consume(char c) { if (position_ < text_.size() && text_[position_] == c) { ++position_; return true; } return false; }
  uint32_t hex() { uint32_t v = 0; for (int i = 0; i < 4; ++i) { const char c = take(); uint32_t n = 0;
    if (c >= '0' && c <= '9') n = c - '0'; else if (c >= 'a' && c <= 'f') n = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') n = c - 'A' + 10; else InvalidJson(); v = (v << 4) | n; } return v; }
  static void append(std::string& out, uint32_t cp) {
    if (cp < 0x80) out.push_back(static_cast<char>(cp));
    else if (cp < 0x800) { out.push_back(static_cast<char>(0xc0 | (cp >> 6))); out.push_back(static_cast<char>(0x80 | (cp & 63))); }
    else if (cp < 0x10000) { out.push_back(static_cast<char>(0xe0 | (cp >> 12))); out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 63))); out.push_back(static_cast<char>(0x80 | (cp & 63))); }
    else { out.push_back(static_cast<char>(0xf0 | (cp >> 18))); out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 63))); out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 63))); out.push_back(static_cast<char>(0x80 | (cp & 63))); }
  }
  std::string string() {
    if (take() != '"') InvalidJson(); std::string out;
    for (;;) { const char c = take(); if (c == '"') return out;
      if (static_cast<uint8_t>(c) < 32) InvalidJson();
      if (c != '\\') { out.push_back(c); continue; }
      switch (take()) {
        case '"': out += '"'; break; case '\\': out += '\\'; break; case '/': out += '/'; break;
        case 'b': out += '\b'; break; case 'f': out += '\f'; break; case 'n': out += '\n'; break; case 'r': out += '\r'; break; case 't': out += '\t'; break;
        case 'u': { auto cp = hex(); if (cp >= 0xd800 && cp <= 0xdbff) {
          if (take() != '\\' || take() != 'u') InvalidJson(); const auto low = hex();
          if (low < 0xdc00 || low > 0xdfff) InvalidJson(); cp = 0x10000 + ((cp - 0xd800) << 10) + low - 0xdc00;
        } else if (cp >= 0xdc00 && cp <= 0xdfff) InvalidJson(); append(out, cp); break; }
        default: InvalidJson();
      }
    }
  }
  Json item(size_t depth) {
    if (depth > 40) InvalidJson(); space(); if (position_ == text_.size()) InvalidJson();
    const char c = text_[position_];
    if (c == '"') return Json(string());
    if (consume('{')) { Json::Object out; space(); if (consume('}')) return Json(std::move(out));
      for (;;) { space(); auto key = string(); space(); if (!consume(':')) InvalidJson(); auto v = item(depth + 1);
        if (!out.emplace(std::move(key), std::move(v)).second) InvalidJson(); space(); if (consume('}')) break; if (!consume(',')) InvalidJson(); }
      return Json(std::move(out)); }
    if (consume('[')) { Json::Array out; space(); if (consume(']')) return Json(std::move(out));
      for (;;) { out.push_back(item(depth + 1)); space(); if (consume(']')) break; if (!consume(',')) InvalidJson(); } return Json(std::move(out)); }
    for (const auto& literal : {std::string("null"), std::string("true"), std::string("false")}) {
      if (text_.compare(position_, literal.size(), literal) == 0) { position_ += literal.size(); if (literal == "null") return Json(); return Json(literal == "true"); }
    }
    const size_t start = position_; consume('-');
    if (!consume('0')) { if (position_ == text_.size() || text_[position_] < '1' || text_[position_] > '9') InvalidJson();
      while (position_ < text_.size() && text_[position_] >= '0' && text_[position_] <= '9') ++position_; }
    bool integral = true;
    if (consume('.')) { integral = false; digits(); }
    if (consume('e') || consume('E')) { integral = false; if (!consume('+')) consume('-'); digits(); }
    const auto* begin = text_.data() + start; const auto* end = text_.data() + position_;
    if (integral) { int64_t v = 0; const auto result = std::from_chars(begin, end, v); if (result.ec == std::errc() && result.ptr == end) return Json(v); }
    double v = 0; const auto result = std::from_chars(begin, end, v); if (result.ec != std::errc() || result.ptr != end || !std::isfinite(v)) InvalidJson(); return Json(v);
  }
  void digits() { const size_t start = position_; while (position_ < text_.size() && text_[position_] >= '0' && text_[position_] <= '9') ++position_; if (position_ == start) InvalidJson(); }
};
inline Json Decode(const std::string& value) { return JsonReader(value).read(); }
inline void Quote(std::string& out, const std::string& text) {
  if (!ValidUtf8(text)) InvalidJson(); out += '"'; constexpr char hex[] = "0123456789abcdef";
  for (const unsigned char c : text) { if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
    else if (c < 32) { out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15]; } else out += static_cast<char>(c); }
  out += '"';
}
inline void EncodeInto(std::string& out, const Json& v, size_t depth = 0) {
  if (depth > 40 || out.size() >= kFrameBytes) InvalidJson();
  if (std::holds_alternative<std::nullptr_t>(v.value)) out += "null";
  else if (const auto* boolean = std::get_if<bool>(&v.value)) out += *boolean ? "true" : "false";
  else if (const auto* integer = std::get_if<int64_t>(&v.value)) out += std::to_string(*integer);
  else if (const auto* number = std::get_if<double>(&v.value)) { char buffer[64]; if (!std::isfinite(*number)) InvalidJson();
    const auto result = std::to_chars(buffer, buffer + sizeof(buffer), *number); if (result.ec != std::errc()) InvalidJson(); out.append(buffer, result.ptr); }
  else if (const auto* text = std::get_if<std::string>(&v.value)) Quote(out, *text);
  else if (const auto* object = std::get_if<Json::Object>(&v.value)) { out += '{'; bool first = true;
    for (const auto& [k, item] : *object) { if (!first) out += ','; first = false; Quote(out, k); out += ':'; EncodeInto(out, item, depth + 1); } out += '}'; }
  else { out += '['; bool first = true; for (const auto& item : std::get<Json::Array>(v.value)) { if (!first) out += ','; first = false; EncodeInto(out, item, depth + 1); } out += ']'; }
  if (out.size() >= kFrameBytes) InvalidJson();
}
inline std::string Encode(const Json& value) { std::string out; EncodeInto(out, value); return out; }
inline bool CanonicalUuid(const std::string& value) {
  if (value.size() != 36 || value[14] != '4' || std::string("89ab").find(value[19]) == std::string::npos) return false;
  for (size_t i = 0; i < value.size(); ++i) { if (i == 8 || i == 13 || i == 18 || i == 23) { if (value[i] != '-') return false; }
    else if (!((value[i] >= '0' && value[i] <= '9') || (value[i] >= 'a' && value[i] <= 'f'))) return false; } return true;
}
// A bounded incremental line decoder shared with the pipe reader. The caller
// reads no more than capacity(), so a partial UTF-8 sequence is never decoded
// until its complete newline-terminated frame is available.
class LineBuffer {
 public:
  bool HasFrame() const { return bytes_.find('\n') != std::string::npos; }
  size_t capacity() const { return kFrameBytes - bytes_.size(); }
  void Push(const char* data, size_t length) {
    if (length > capacity()) InvalidJson(); bytes_.append(data, length);
    if (bytes_.size() == kFrameBytes && bytes_.find('\n') == std::string::npos) InvalidJson();
  }
  bool Take(std::string& frame) {
    const auto end = bytes_.find('\n'); if (end == std::string::npos) return false;
    frame = bytes_.substr(0, end); bytes_.erase(0, end + 1);
    if (!frame.empty() && frame.back() == '\r') frame.pop_back();
    if (!ValidUtf8(frame)) InvalidJson(); return true;
  }
 private:
  std::string bytes_;
};
}  // namespace sd::mcp
