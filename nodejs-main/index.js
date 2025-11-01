const express = require("express");
const axios = require("axios");
const os = require("os");
const fs = require("fs");
const path = require("path");
const { promisify } = require("util");
const { execSync } = require("child_process");
const exec = promisify(require("child_process").exec);

const CONFIG = {
  UPLOAD_URL: process.env.UPLOAD_URL || "",
  PROJECT_URL: process.env.PROJECT_URL || "",
  AUTO_ACCESS: process.env.AUTO_ACCESS === "true",
  FILE_PATH: process.env.FILE_PATH || "./tmp",
  SUB_PATH: process.env.SUB_PATH || "sub",
  PORT: process.env.SERVER_PORT || process.env.PORT || 3000,
  UUID: process.env.UUID || "9afd1229-b893-40c1-84dd-51e7ce204913",
  ARGO_DOMAIN: process.env.ARGO_DOMAIN || "",
  ARGO_AUTH: process.env.ARGO_AUTH || "",
  ARGO_PORT: process.env.ARGO_PORT || 8001,
  CFIP: process.env.CFIP || "cdns.doon.eu.org",
  CFPORT: process.env.CFPORT || 443,
  NAME: process.env.NAME || "",
};

const FILES = {
  web: path.join(CONFIG.FILE_PATH, "web"),
  bot: path.join(CONFIG.FILE_PATH, "bot"),
  sub: path.join(CONFIG.FILE_PATH, "sub.txt"),
  list: path.join(CONFIG.FILE_PATH, "list.txt"),
  bootLog: path.join(CONFIG.FILE_PATH, "boot.log"),
  config: path.join(CONFIG.FILE_PATH, "config.json"),
  tunnelJson: path.join(CONFIG.FILE_PATH, "tunnel.json"),
  tunnelYaml: path.join(CONFIG.FILE_PATH, "tunnel.yml"),
};

// 初始化目录
function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`${dir} created`);
  } else {
    console.log(`${dir} already exists`);
  }
}
ensureDir(CONFIG.FILE_PATH);

// 清理历史文件
function cleanupFiles() {
  ["web", "bot", "sub.txt", "boot.log"].forEach((f) => {
    const fp = path.join(CONFIG.FILE_PATH, f);
    if (fs.existsSync(fp)) fs.unlinkSync(fp);
  });
}

// 删除历史节点
async function deleteNodes() {
  if (!CONFIG.UPLOAD_URL || !fs.existsSync(FILES.sub)) return;
  try {
    const fileContent = fs.readFileSync(FILES.sub, "utf-8");
    const decoded = Buffer.from(fileContent, "base64").toString("utf-8");
    const nodes = decoded.split("\n").filter((line) =>
      /(vless|vmess|trojan|hysteria2|tuic):\/\//.test(line)
    );
    if (nodes.length) {
      await axios.post(
        `${CONFIG.UPLOAD_URL}/api/delete-nodes`,
        { nodes },
        { headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (e) {
    // 忽略异常
  }
}

// 生成配置文件
function writeConfig() {
  const config = {
    log: { access: "/dev/null", error: "/dev/null", loglevel: "none" },
    inbounds: [
      {
        port: CONFIG.ARGO_PORT,
        protocol: "vless",
        settings: {
          clients: [{ id: CONFIG.UUID, flow: "xtls-rprx-vision" }],
          decryption: "none",
          fallbacks: [
            { dest: 3001 },
            { path: "/vless-argo", dest: 3002 },
            { path: "/vmess-argo", dest: 3003 },
            { path: "/trojan-argo", dest: 3004 },
          ],
        },
        streamSettings: { network: "tcp" },
      },
      {
        port: 3001,
        listen: "127.0.0.1",
        protocol: "vless",
        settings: { clients: [{ id: CONFIG.UUID }], decryption: "none" },
        streamSettings: { network: "tcp", security: "none" },
      },
      {
        port: 3002,
        listen: "127.0.0.1",
        protocol: "vless",
        settings: { clients: [{ id: CONFIG.UUID, level: 0 }], decryption: "none" },
        streamSettings: {
          network: "ws",
          security: "none",
          wsSettings: { path: "/vless-argo" },
        },
        sniffing: {
          enabled: true,
          destOverride: ["http", "tls", "quic"],
          metadataOnly: false,
        },
      },
      {
        port: 3003,
        listen: "127.0.0.1",
        protocol: "vmess",
        settings: { clients: [{ id: CONFIG.UUID, alterId: 0 }] },
        streamSettings: { network: "ws", wsSettings: { path: "/vmess-argo" } },
        sniffing: {
          enabled: true,
          destOverride: ["http", "tls", "quic"],
          metadataOnly: false,
        },
      },
      {
        port: 3004,
        listen: "127.0.0.1",
        protocol: "trojan",
        settings: { clients: [{ password: CONFIG.UUID }] },
        streamSettings: {
          network: "ws",
          security: "none",
          wsSettings: { path: "/trojan-argo" },
        },
        sniffing: {
          enabled: true,
          destOverride: ["http", "tls", "quic"],
          metadataOnly: false,
        },
      },
    ],
    dns: { servers: ["https+local://8.8.8.8/dns-query"] },
    outbounds: [
      { protocol: "freedom", tag: "direct" },
      { protocol: "blackhole", tag: "block" },
    ],
  };
  fs.writeFileSync(FILES.config, JSON.stringify(config, null, 2));
}

// 判断系统架构
function getArch() {
  const arch = os.arch();
  return ["arm", "arm64", "aarch64"].includes(arch) ? "arm" : "amd";
}

// 下载文件
function downloadFile(fileName, url) {
  return new Promise((resolve, reject) => {
    const filePath = path.join(CONFIG.FILE_PATH, fileName);
    const writer = fs.createWriteStream(filePath);
    axios({ method: "get", url, responseType: "stream" })
      .then((res) => {
        res.data.pipe(writer);
        writer.on("finish", () => resolve(fileName));
        writer.on("error", (err) => {
          fs.unlink(filePath, () => {});
          reject(err);
        });
      })
      .catch(reject);
  });
}

// 下载并授权运行依赖
async function setupBinaries() {
  const arch = getArch();
  const files = arch === "arm"
    ? [
        { name: "web", url: "https://arm64.ssss.nyc.mn/web" },
        { name: "bot", url: "https://arm64.ssss.nyc.mn/bot" },
      ]
    : [
        { name: "web", url: "https://amd64.ssss.nyc.mn/web" },
        { name: "bot", url: "https://amd64.ssss.nyc.mn/bot" },
      ];
  await Promise.all(files.map(f => downloadFile(f.name, f.url)));
  ["web", "bot"].forEach((f) => {
    const fp = path.join(CONFIG.FILE_PATH, f);
    if (fs.existsSync(fp)) fs.chmodSync(fp, 0o775);
  });
}

// 生成隧道配置
function writeArgoConfig() {
  if (!CONFIG.ARGO_AUTH || !CONFIG.ARGO_DOMAIN) return;
  if (CONFIG.ARGO_AUTH.includes("TunnelSecret")) {
    fs.writeFileSync(FILES.tunnelJson, CONFIG.ARGO_AUTH);
    const tunnelId = CONFIG.ARGO_AUTH.split('"')[11];
    const yaml = `
tunnel: ${tunnelId}
credentials-file: ${FILES.tunnelJson}
protocol: http2

ingress:
  - hostname: ${CONFIG.ARGO_DOMAIN}
    service: http://localhost:${CONFIG.ARGO_PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
`;
    fs.writeFileSync(FILES.tunnelYaml, yaml);
  }
}

// 启动服务进程
async function runProcesses() {
  // 启动 web
  await exec(`nohup ${FILES.web} -c ${FILES.config} > /dev/null 2>&1 &`);
  // 启动 bot
  let args;
  if (CONFIG.ARGO_AUTH.match(/^[A-Z0-9a-z=]{120,250}$/)) {
    args = `tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${CONFIG.ARGO_AUTH}`;
  } else if (CONFIG.ARGO_AUTH.includes("TunnelSecret")) {
    args = `tunnel --edge-ip-version auto --config ${FILES.tunnelYaml} run`;
  } else {
    args = `tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ${FILES.bootLog} --loglevel info --url http://localhost:${CONFIG.ARGO_PORT}`;
  }
  await exec(`nohup ${FILES.bot} ${args} > /dev/null 2>&1 &`);
}

// 提取域名并生成订阅
async function extractDomainAndGenerateSub(app) {
  let argoDomain = CONFIG.ARGO_DOMAIN;
  if (!argoDomain) {
    // 读取 boot.log 获取域名
    let found = false;
    for (let i = 0; i < 3 && !found; i++) {
      if (fs.existsSync(FILES.bootLog)) {
        const content = fs.readFileSync(FILES.bootLog, "utf-8");
        const match = content.match(/https?:\/\/([^ ]*trycloudflare\.com)/);
        if (match) {
          argoDomain = match[1];
          found = true;
        }
      }
      if (!found) await new Promise(r => setTimeout(r, 2000));
    }
    if (!argoDomain) throw new Error("ArgoDomain not found");
  }
  // 生成订阅
  const metaInfo = execSync(
    'curl -sm 5 https://speed.cloudflare.com/meta | awk -F\\" \'{print $26"-"$18}\' | sed -e \'s/ /_/g\'',
    { encoding: "utf-8" }
  ).trim();
  const nodeName = CONFIG.NAME ? `${CONFIG.NAME}-${metaInfo}` : metaInfo;
  const VMESS = {
    v: "2",
    ps: nodeName,
    add: CONFIG.CFIP,
    port: CONFIG.CFPORT,
    id: CONFIG.UUID,
    aid: "0",
    scy: "none",
    net: "ws",
    type: "none",
    host: argoDomain,
    path: "/vmess-argo?ed=2560",
    tls: "tls",
    sni: argoDomain,
    alpn: "",
    fp: "chrome",
  };
  const subTxt = `
vless://${CONFIG.UUID}@${CONFIG.CFIP}:${CONFIG.CFPORT}?encryption=none&security=tls&sni=${argoDomain}&fp=chrome&type=ws&host=${argoDomain}&path=%2Fvless-argo%3Fed%3D2560#${nodeName}

vmess://${Buffer.from(JSON.stringify(VMESS)).toString("base64")}

trojan://${CONFIG.UUID}@${CONFIG.CFIP}:${CONFIG.CFPORT}?security=tls&sni=${argoDomain}&fp=chrome&type=ws&host=${argoDomain}&path=%2Ftrojan-argo%3Fed%3D2560#${nodeName}
`;
  const encodedSub = Buffer.from(subTxt).toString("base64");
  fs.writeFileSync(FILES.sub, encodedSub);
  app.get(`/${CONFIG.SUB_PATH}`, (req, res) => {
    res.set("Content-Type", "text/plain; charset=utf-8");
    res.send(encodedSub);
  });
  await uploadNodes();
}

// 上传节点/订阅
async function uploadNodes() {
  if (CONFIG.UPLOAD_URL && CONFIG.PROJECT_URL) {
    const subscriptionUrl = `${CONFIG.PROJECT_URL}/${CONFIG.SUB_PATH}`;
    await axios.post(
      `${CONFIG.UPLOAD_URL}/api/add-subscriptions`,
      { subscription: [subscriptionUrl] },
      { headers: { "Content-Type": "application/json" } }
    );
  } else if (CONFIG.UPLOAD_URL && fs.existsSync(FILES.list)) {
    const content = fs.readFileSync(FILES.list, "utf-8");
    const nodes = content.split("\n").filter((line) =>
      /(vless|vmess|trojan|hysteria2|tuic):\/\//.test(line)
    );
    if (nodes.length) {
      await axios.post(
        `${CONFIG.UPLOAD_URL}/api/add-nodes`,
        { nodes },
        { headers: { "Content-Type": "application/json" } }
      );
    }
  }
}

// 自动访问项目URL
async function autoVisit() {
  if (CONFIG.AUTO_ACCESS && CONFIG.PROJECT_URL) {
    await axios.post(
      "https://oooo.serv00.net/add-url",
      { url: CONFIG.PROJECT_URL },
      { headers: { "Content-Type": "application/json" } }
    );
  }
}

// 定时清理文件
function scheduleCleanup() {
  setTimeout(() => {
    [FILES.bootLog, FILES.config, FILES.web, FILES.bot].forEach((f) => {
      if (fs.existsSync(f)) fs.unlinkSync(f);
    });
    console.clear();
    console.log("App is running\nThank you for using this script, enjoy!");
  }, 90000);
}

// 主流程
async function main() {
  const app = express();
  app.get("/", (req, res) => res.send("Hello world!"));

  await deleteNodes();
  cleanupFiles();
  writeConfig();
  writeArgoConfig();
  await setupBinaries();
  await runProcesses();
  await extractDomainAndGenerateSub(app);
  await autoVisit();
  scheduleCleanup();

  app.listen(CONFIG.PORT, () =>
    console.log(`http server is running on port:${CONFIG.PORT}!`)
  );
}

main().catch((err) => {
  console.error("Fatal error:", err);
});