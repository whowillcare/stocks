import http from "http";
import fetch from "node-fetch";
import { Readable } from "stream";

const PORT = process.env.PROXY_PORT || 8080;

const bannedHeader = [
	'referrer-policy','vary','content-encoding'

];
const server = http.createServer(async (req, res) => {
  try {
    const targetURL = req.url.slice(1);

    if (!targetURL.startsWith("http://") && !targetURL.startsWith("https://")) {
      res.writeHead(400, { "Content-Type": "text/plain" });
      res.end("Usage: /https://example.com/path");
      return;
    }

const browserHeaders = {
  "user-agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "accept":
    "text/html,application/xhtml+xml,application/xml;q=0.9,"
    + "*/*;q=0.8",
  "accept-language": "en-US,en;q=0.9",
  "upgrade-insecure-requests": "1",
};

const headers= {
    // ...req.headers,
    ...browserHeaders,
    connection: 'close',
    host: new URL(targetURL).host,
};
console.log("Requesting with headers",headers);
const upstreamRes = await fetch(targetURL, {
  method: req.method,
  headers: {
	  ...headers
  },
  body: ["GET", "HEAD"].includes(req.method) ? undefined : req,
  redirect: "manual",
  duplex: "half",
});


    // Make sure headers are sent only once

    if (!res.headersSent) {
      const respHeaders = 
        Object.fromEntries(upstreamRes.headers);
      const downHeaders={}
	    for(let k in respHeaders){
		    if (k.startsWith('x-') || ( bannedHeader.includes(k))){
			    continue;
		    }
		    downHeaders[k]=respHeaders[k];
	    }
	    console.log("Resp header",respHeaders);
	    console.log("Down header",downHeaders);
      res.writeHead(upstreamRes.status, {
	      ...downHeaders,
        "access-control-allow-origin": "*",
      });
    }

    // upstreamRes.body may be a Web stream OR a Node stream
    let stream;

    if (typeof upstreamRes.body.getReader === "function") {
      // Web ReadableStream → Node stream
      stream = Readable.fromWeb(upstreamRes.body);
    } else {
      // Already a Node.js stream (PassThrough)
      stream = upstreamRes.body;
    }

    stream.pipe(res);
  } catch (err) {
    console.error("Proxy error:", err);

    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "text/plain" });
    }
    res.end("Proxy error: " + err.message);
  }
});

server.listen(PORT, () => {
  console.log(`Proxy running on http://localhost:${PORT}`);
});
