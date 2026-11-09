/**
 * GenImage Native Messaging Host (Node.js)
 * Nhiệm vụ:
 * 1. Xác thực chính xác 100% đường dẫn đầy đủ trên ổ cứng của thư mục đã chọn (dựa trên file marker / file ảnh vừa lưu).
 * 2. Mở trực tiếp cửa sổ Windows File Explorer (explorer.exe) đến đúng đường dẫn thư mục đã chọn mà KHÔNG gọi chrome.downloads.download (tránh hoàn toàn cửa sổ Save As).
 */

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

const SKIP_DIRS = new Set([
  "windows",
  "program files",
  "program files (x86)",
  "programdata",
  "$recycle.bin",
  "system volume information",
  "recovery",
  "perflogs",
  "appdata",
  "node_modules",
  ".git",
  ".gemini",
  ".vscode",
  ".idea",
  "venv",
  ".venv",
  "__pycache__",
  "dist",
  "build"
]);

function readMessageFromStdin() {
  return new Promise((resolve) => {
    let chunks = [];
    let totalLen = 0;
    let expectedLen = null;

    const timer = setTimeout(() => {
      resolve({});
    }, 4000);

    process.stdin.on("readable", () => {
      let chunk;
      while ((chunk = process.stdin.read()) !== null) {
        chunks.push(chunk);
        totalLen += chunk.length;
        const buf = Buffer.concat(chunks, totalLen);
        if (expectedLen === null && buf.length >= 4) {
          expectedLen = buf.readUInt32LE(0);
        }
        if (expectedLen !== null && buf.length >= 4 + expectedLen) {
          clearTimeout(timer);
          const jsonStr = buf.slice(4, 4 + expectedLen).toString("utf8");
          try {
            resolve(JSON.parse(jsonStr));
          } catch {
            resolve({});
          }
          return;
        }
      }
    });

    process.stdin.on("end", () => {
      clearTimeout(timer);
      resolve({});
    });
  });
}

function writeMessageToStdout(obj) {
  const payload = Buffer.from(JSON.stringify(obj), "utf8");
  const header = Buffer.alloc(4);
  header.writeUInt32LE(payload.length, 0);
  process.stdout.write(Buffer.concat([header, payload]));
}

function dirMatchesCriteria(dirPath, verifyFileName, sampleFiles) {
  try {
    if (verifyFileName) {
      return fs.existsSync(path.join(dirPath, verifyFileName));
    }
    if (Array.isArray(sampleFiles) && sampleFiles.length > 0) {
      for (const sf of sampleFiles) {
        if (sf && fs.existsSync(path.join(dirPath, sf))) {
          return true;
        }
      }
      return false;
    }
    return fs.existsSync(dirPath);
  } catch {
    return false;
  }
}

function searchDirRecursive(rootDir, targetFolderLower, verifyFileName, sampleFiles, maxDepth, visited) {
  if (maxDepth < 0 || !rootDir) return null;
  const normRoot = path.resolve(rootDir);
  const normLower = normRoot.toLowerCase();
  if (visited.has(normLower)) return null;
  visited.add(normLower);

  try {
    const baseName = path.basename(normRoot).toLowerCase();
    if (baseName === targetFolderLower || (!baseName && normRoot.toLowerCase().startsWith(targetFolderLower))) {
      if (dirMatchesCriteria(normRoot, verifyFileName, sampleFiles)) {
        return normRoot;
      }
    }
  } catch {}

  if (maxDepth === 0) return null;

  let entries;
  try {
    entries = fs.readdirSync(normRoot, { withFileTypes: true });
  } catch {
    return null;
  }

  // Kiểm tra các thư mục con trực tiếp có tên trùng khớp trước (ưu tiên chiều rộng ở tầng hiện tại)
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const nameLower = entry.name.toLowerCase();
    if (nameLower === targetFolderLower) {
      const candidatePath = path.join(normRoot, entry.name);
      if (dirMatchesCriteria(candidatePath, verifyFileName, sampleFiles)) {
        return candidatePath;
      }
    }
  }

  // Duyệt đệ quy xuống các thư mục con
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const nameLower = entry.name.toLowerCase();
    if (nameLower.startsWith(".") || SKIP_DIRS.has(nameLower)) continue;
    // Tránh quét lại C:\Users khi đang quét từ ổ C:\ vì đã quét homedir riêng
    if (normLower === "c:\\" && nameLower === "users") continue;

    const childPath = path.join(normRoot, entry.name);
    const found = searchDirRecursive(
      childPath,
      targetFolderLower,
      verifyFileName,
      sampleFiles,
      maxDepth - 1,
      visited
    );
    if (found) return found;
  }

  return null;
}

function isAbsoluteDiskPath(p) {
  if (!p) return false;
  const s = String(p).trim();
  return s.includes(":") || s.startsWith("/");
}

function findExactFolderOnDisk(msg) {
  const isWin = process.platform === "win32";
  const rawFolderPath = String(msg.folderPath || "").trim();
  const folderPath = isWin ? rawFolderPath.replace(/\//g, "\\") : rawFolderPath.replace(/\\/g, "/");
  const folderName = String(msg.folderName || "").trim();
  const verifyFileName = String(msg.verifyFileName || msg.markerFileName || "").trim();
  const sampleFiles = Array.isArray(msg.sampleFiles) ? msg.sampleFiles : [];
  const targetLower = folderName.toLowerCase();

  // 1. Nếu folderPath đã là đường dẫn đầy đủ và chứa đúng verifyFileName -> chính xác 100%
  if (isAbsoluteDiskPath(folderPath)) {
    try {
      if (verifyFileName && fs.existsSync(path.join(folderPath, verifyFileName))) {
        return folderPath;
      }
    } catch {}
  }

  const homeDir = os.homedir();
  const priorityRoots = [
    path.join(homeDir, "Downloads"),
    path.join(homeDir, "Desktop"),
    path.join(homeDir, "Pictures"),
    path.join(homeDir, "Documents"),
    homeDir
  ];

  // 2. Kiểm tra nhanh các thư mục con trực tiếp trong Downloads/Desktop/Pictures/Documents/Home trước khi duyệt đệ quy (tránh TCC prompt trên macOS)
  if (targetLower) {
    for (const root of priorityRoots) {
      try {
        if (path.basename(root).toLowerCase() === targetLower && dirMatchesCriteria(root, verifyFileName, sampleFiles)) {
          return root;
        }
        const directCand = path.join(root, folderName);
        if (dirMatchesCriteria(directCand, verifyFileName, sampleFiles)) {
          return directCand;
        }
      } catch {}
    }
  }

  // 3. Nếu có verifyFileName hoặc sampleFiles, tìm chính xác thư mục chứa file đó
  if (verifyFileName || sampleFiles.length > 0) {
    const visited = new Set();

    for (const root of priorityRoots) {
      if (!fs.existsSync(root)) continue;
      const depth = root === homeDir ? 3 : 4;
      const found = searchDirRecursive(root, targetLower, verifyFileName, sampleFiles, depth, visited);
      if (found) return found;
    }

    const extraRoots = isWin
      ? ["D:\\", "E:\\", "F:\\", "G:\\", "C:\\"]
      : ["/Volumes", "/Users"];
    for (const drv of extraRoots) {
      if (!fs.existsSync(drv)) continue;
      const found = searchDirRecursive(drv, targetLower, verifyFileName, sampleFiles, 4, visited);
      if (found) return found;
    }
  }

  // 3. Nếu folderPath có sẵn và tồn tại trên ổ cứng
  if (isAbsoluteDiskPath(folderPath) && fs.existsSync(folderPath)) {
    return folderPath;
  }

  // 4. Kiểm tra các thư mục phổ biến theo tên folderName
  if (targetLower) {
    for (const root of priorityRoots) {
      if (path.basename(root).toLowerCase() === targetLower && fs.existsSync(root)) {
        return root;
      }
      const candidate = path.join(root, folderName);
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
  }

  return folderPath || "";
}

async function main() {
  const msg = await readMessageFromStdin();
  const action = String(msg.action || "").toUpperCase();

  const resolvedDir = findExactFolderOnDisk(msg);

  if (action === "OPEN_EXPLORER") {
    if (resolvedDir && fs.existsSync(resolvedDir)) {
      try {
        const isMac = process.platform === "darwin";
        const cmd = isMac ? "open" : process.platform === "win32" ? "explorer.exe" : "xdg-open";
        const child = spawn(cmd, [resolvedDir], {
          detached: true,
          stdio: "ignore",
          windowsHide: false
        });
        child.unref();

        // Đợi lệnh mở Finder / File Explorer hoàn tất bàn giao cho hệ điều hành
        await Promise.race([
          new Promise((resolve) => child.on("exit", resolve)),
          new Promise((resolve) => child.on("error", resolve)),
          new Promise((resolve) => setTimeout(resolve, 900))
        ]);

        writeMessageToStdout({
          ok: true,
          opened: true,
          fullPath: resolvedDir
        });
        return;
      } catch (err) {
        writeMessageToStdout({
          ok: false,
          error: err.message,
          fullPath: resolvedDir
        });
        return;
      }
    }
    writeMessageToStdout({
      ok: false,
      error: "Folder not found on disk",
      fullPath: resolvedDir
    });
    return;
  }

  // Mặc định: RESOLVE_FOLDER
  writeMessageToStdout({
    ok: Boolean(resolvedDir),
    fullPath: resolvedDir
  });
}

main().catch((err) => {
  writeMessageToStdout({ ok: false, error: err?.message || "unknown_error" });
});

