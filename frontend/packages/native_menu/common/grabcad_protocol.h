#ifndef PROTOTYPE_GRABCAD_PROTOCOL_H_
#define PROTOTYPE_GRABCAD_PROTOCOL_H_
#include <string>

namespace grabcad {
// Quote untrusted UTF-8 values as JS/JSON string literals, never as code.
inline std::string Quote(const std::string &input) {
  const char *hex = "0123456789abcdef";
  std::string out = "\"";
  for (unsigned char c : input) {
    if (c == '"' || c == '\\') {
      out += '\\';
      out += static_cast<char>(c);
    } else if (c < 32) {
      out += "\\u00";
      out += hex[c >> 4];
      out += hex[c & 15];
    } else {
      out += static_cast<char>(c);
    }
  }
  return out + '"';
}
inline bool MetadataPath(const std::string &path) {
  if (path != "models" && path.rfind("models/", 0) != 0)
    return false;
  std::string decoded;
  for (size_t i = 0; i < path.size(); ++i) {
    unsigned char c = static_cast<unsigned char>(path[i]);
    if (c == '%' && i + 2 < path.size()) {
      auto hex = [](char v) -> int {
        if (v >= '0' && v <= '9')
          return v - '0';
        if (v >= 'a' && v <= 'f')
          return v - 'a' + 10;
        if (v >= 'A' && v <= 'F')
          return v - 'A' + 10;
        return -1;
      };
      int a = hex(path[i + 1]), b = hex(path[i + 2]);
      if (a < 0 || b < 0)
        return false;
      c = static_cast<unsigned char>(a * 16 + b);
      i += 2;
    }
    if (c < 32 || c == 127 || c == '#' || c == '\\' || c == '%')
      return false;
    decoded += static_cast<char>(c);
  }
  if (decoded.find("..") != std::string::npos)
    return false;
  return path.size() <= 4096;
}
inline bool FileName(const std::string &name) {
  if (name.empty() || name == "." || name == ".." || name.size() > 240)
    return false;
  for (unsigned char c : name) {
    if (c < 32 || c == 127 ||
        std::string("\\/:*?\"<>|").find(static_cast<char>(c)) !=
            std::string::npos)
      return false;
  }
  return name.back() != '.' && name.back() != ' ';
}
inline bool GrabCadUrl(const std::string &url) {
  return url.rfind("https://grabcad.com/", 0) == 0 &&
         url.find_first_of("\r\n\\") == std::string::npos;
}
inline std::string RequestScript(const std::string &id, const std::string &path,
                                 const std::string *body) {
  // A framed string keeps response parsing native and avoids serialising
  // credentials/account data through any JSON codec.
  return "(async()=>{const "
         "post=m=>(window.chrome?.webview||window.webkit?.messageHandlers?."
         "prototype).postMessage(m);const id=" +
         Quote(id) +
         ";"
         "if(location.origin!=='https://"
         "grabcad.com'){post(id+'\\n-1\\naccess_denied');return;}"
         "window.__prototypeRequests=window.__prototypeRequests||{};const "
         "c=new AbortController();window.__prototypeRequests[id]=c;"
         "const timer=setTimeout(()=>c.abort(),20000);try{const "
         "headers={Accept:'application/json'};"
         "const "
         "token=document.querySelector('meta[name=\"csrf-token\"]')?.content;"
         "if(token)headers['X-CSRF-Token']=token;" +
         std::string(body ? "headers['Content-Type']='application/json';"
                          : "") +
         "const r=await fetch('/community/api/v1/'+" + Quote(path) +
         ",{credentials:'same-origin',redirect:'manual',signal:c.signal,"
         "headers,method:" +
         Quote(body ? "POST" : "GET") + (body ? ",body:" + Quote(*body) : "") +
         "});"
         "if(r.type==='opaqueredirect'||!r.url.startsWith('https://grabcad.com/"
         "community/api/v1/'))throw "
         "Error('access_denied');"
         "const type=r.headers.get('content-type')||'';"
         "const text=r.status===200&&type.includes('application/json')?await "
         "r.text():'';if(text.length>8388608)throw "
         "Error('invalid_response');"
         "post(id+'\\n'+r.status+'\\n'+type+'"
         "\\n'+text);"
         "}catch(e){post(id+'\\n-1\\n'+(e.name==='AbortError'?'timeout':"
         "e.message==='access_denied'?'access_denied':e.message==='invalid_"
         "response'?'invalid_response':'unavailable'));}"
         "finally{clearTimeout(timer);delete "
         "window.__prototypeRequests[id];}})();";
}
inline std::string LoginScript() {
  return "(async()=>{const "
         "post=m=>(window.chrome?.webview||window.webkit?.messageHandlers?."
         "prototype).postMessage(m);"
         "if(location.origin!=='https://grabcad.com'){post('auth\\n0');return;}"
         "try{const r=await "
         "fetch('/community/api/v1/members/me',{credentials:'same-origin'});"
         "const d=r.ok&&r.status!==204?await r.json():null;"
         "post('auth\\n'+(d&&(d.id||d.member?.id)?'1':'0'));"
         "}catch(e){post('auth\\nerror');}})();";
}
} // namespace grabcad
#endif
