const http = require("http");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "build");
const PORT = process.env.PORT || 3000;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".eot": "application/vnd.ms-fontobject",
  ".map": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

http
  .createServer((req, res) => {
    let urlPath;
    try {
      urlPath = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    } catch {
      urlPath = "/";
    }
    if (urlPath === "/") urlPath = "/index.html";

    let filePath = path.normalize(path.join(ROOT, urlPath));
    if (!filePath.startsWith(ROOT)) filePath = path.join(ROOT, "index.html");

    fs.readFile(filePath, (err, data) => {
      if (!err) {
        res.writeHead(200, {
          "Content-Type": MIME[path.extname(filePath).toLowerCase()] || "application/octet-stream",
          "Cache-Control": "no-store",
        });
        return res.end(data);
      }

      if (path.extname(urlPath) !== "") {
        res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
        return res.end("Not found");
      }

      fs.readFile(path.join(ROOT, "index.html"), (err2, index) => {
        if (err2) {
          res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
          return res.end("index.html missing - run `npm run build` first");
        }
        res.writeHead(200, { "Content-Type": MIME[".html"], "Cache-Control": "no-store" });
        res.end(index);
      });
    });
  })
  .listen(PORT, () => {
    console.log(`Anyshelf static server: http://localhost:${PORT} (serving ${ROOT})`);
  });
