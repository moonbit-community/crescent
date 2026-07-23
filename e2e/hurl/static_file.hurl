# Capture an ETag from a real file-system response and reuse it to verify
# HEAD and conditional request behavior.

GET {{host}}/assets/hello.txt
HTTP 200
[Captures]
etag: header "ETag"
[Asserts]
header "Content-Type" startsWith "text/plain"
header "Content-Length" == "16"
body == "hello from disk\n"

HEAD {{host}}/assets/hello.txt
HTTP 200
[Asserts]
bytes count == 0
header "Content-Length" == "16"
header "ETag" == "{{etag}}"

GET {{host}}/assets/hello.txt
If-None-Match: {{etag}}
HTTP 304
[Asserts]
bytes count == 0
header "ETag" == "{{etag}}"

GET {{host}}/assets
HTTP 200
[Asserts]
header "Content-Type" startsWith "text/html"
body == "index from disk\n"

GET {{host}}/assets/missing.txt
HTTP 404
[Asserts]
body == "Not Found"
