#!/bin/bash
set -e

APP_NAME="Pomodoro"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$HOME/Desktop/$APP_NAME.app"

echo "=== 编译 Pomodoro 番茄时钟 ==="

# 清理旧构建
rm -rf "$BUILD_DIR/build"
mkdir -p "$BUILD_DIR/build"

# ---- 1. 生成 App 图标 ----
echo "→ 生成图标..."
cat > "$BUILD_DIR/build/make_icon.swift" << 'ICONSWIFT'
import AppKit
import CoreGraphics

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])

// 创建番茄图标
func makeIcon(size: Int) -> NSImage {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let img = NSImage(size: rect.size)
    img.lockFocus()

    // 深色圆角矩形背景
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size)*0.05, dy: CGFloat(size)*0.05),
                               xRadius: CGFloat(size)*0.22, yRadius: CGFloat(size)*0.22)
    NSColor(red: 0.15, green: 0.13, blue: 0.18, alpha: 1).setFill()
    bgPath.fill()

    // 主体番茄红色
    let center = CGPoint(x: size/2, y: size/2)
    let radius = CGFloat(size) * 0.3
    let tomatoPath = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius * 0.7,
                                                  width: radius * 2, height: radius * 1.8))
    NSColor(red: 0.93, green: 0.28, blue: 0.22, alpha: 1).setFill()
    tomatoPath.fill()

    // 高光
    let highlightPath = NSBezierPath(ovalIn: CGRect(x: center.x - radius*0.3, y: center.y + radius*0.05,
                                                     width: radius*0.6, height: radius*0.4))
    NSColor(red: 1, green: 0.45, blue: 0.35, alpha: 0.35).setFill()
    highlightPath.fill()

    // 叶子
    let leafPath = NSBezierPath()
    leafPath.move(to: NSPoint(x: center.x, y: center.y + radius * 0.85))
    leafPath.curve(to: NSPoint(x: center.x, y: center.y + radius * 1.3),
                   controlPoint1: NSPoint(x: center.x - radius*0.3, y: center.y + radius*1.0),
                   controlPoint2: NSPoint(x: center.x - radius*0.1, y: center.y + radius*1.2))
    leafPath.curve(to: NSPoint(x: center.x, y: center.y + radius * 0.85),
                   controlPoint1: NSPoint(x: center.x + radius*0.1, y: center.y + radius*1.2),
                   controlPoint2: NSPoint(x: center.x + radius*0.3, y: center.y + radius*1.0))
    NSColor(red: 0.15, green: 0.73, blue: 0.25, alpha: 1).setFill()
    leafPath.fill()

    img.unlockFocus()
    return img
}

let fm = FileManager.default
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    let icon = makeIcon(size: size)
    let name = size >= 512 ? "icon_\(size)x\(size)" : "icon_\(size)x\(size)"
    let pngURL = iconset.appendingPathComponent("\(name).png")
    if let cgImg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let rep = NSBitmapImageRep(cgImage: cgImg)
        rep.size = NSSize(width: size, height: size)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: pngURL)
        }
    }
    // @2x for smaller sizes
    if size <= 512 {
        let doubleSize = size * 2
        let dicon = makeIcon(size: doubleSize)
        let dname = "icon_\(size)x\(size)@2x"
        let dpngURL = iconset.appendingPathComponent("\(dname).png")
        if let cgImg = dicon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            rep.size = NSSize(width: doubleSize, height: doubleSize)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: dpngURL)
            }
        }
    }
}

print("OK")
ICONSWIFT

swiftc "$BUILD_DIR/build/make_icon.swift" -o "$BUILD_DIR/build/make_icon"
"$BUILD_DIR/build/make_icon" "$BUILD_DIR/build/$APP_NAME.iconset"

# 使用 iconutil 生成 .icns
iconutil -c icns "$BUILD_DIR/build/$APP_NAME.iconset" -o "$BUILD_DIR/build/AppIcon.icns"
echo "✓ 图标生成完成"

# ---- 2. 生成提示音 ----
echo "→ 生成提示音..."
cat > "$BUILD_DIR/build/make_sound.swift" << 'SOUNDSWIFT'
import AVFoundation
import CoreAudio

let url = URL(fileURLWithPath: CommandLine.arguments[1])

// 生成一个简单的 AIFF 提示音
let sampleRate = 44100.0
let duration = 0.8
let numSamples = Int(sampleRate * duration)

var samples = [Int16](repeating: 0, count: numSamples)

// C-E-G-C 和弦渐强音效
for i in 0..<numSamples {
    let t = Double(i) / sampleRate
    let envelope = min(1.0, t / 0.02) * max(0.0, (duration - t) / duration)
    let freq: Double
    if t < 0.2 { freq = 523.25 }       // C5
    else if t < 0.4 { freq = 659.25 }  // E5
    else if t < 0.6 { freq = 783.99 }  // G5
    else { freq = 1046.5 }              // C6
    let sample = sin(2 * .pi * freq * t) * envelope * 0.7
    samples[i] = Int16(sample * Double(Int16.max))
}

// 写入 AIFF
let dataSize = numSamples * 2
var fileData = Data()

// AIFF header
fileData.append("FORM".data(using: .ascii)!)
var formSize = UInt32(46 + dataSize).bigEndian
fileData.append(Data(bytes: &formSize, count: 4))
fileData.append("AIFF".data(using: .ascii)!)

// COMM chunk
fileData.append("COMM".data(using: .ascii)!)
var commSize = UInt32(18).bigEndian
fileData.append(Data(bytes: &commSize, count: 4))
var numChannels = UInt16(1).bigEndian
fileData.append(Data(bytes: &numChannels, count: 2))
var numSampleFrames = UInt32(numSamples).bigEndian
fileData.append(Data(bytes: &numSampleFrames, count: 4))
var sampleSize = UInt16(16).bigEndian
fileData.append(Data(bytes: &sampleSize, count: 2))
// 44100 Hz in AIFF 80-bit extended float format
fileData.append(contentsOf: [0x40, 0x0E, 0xAC, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

// SSND chunk
fileData.append("SSND".data(using: .ascii)!)
var ssndSize = UInt32(8 + dataSize).bigEndian
fileData.append(Data(bytes: &ssndSize, count: 4))
var offset = UInt32(0).bigEndian
var blockSize = UInt32(0).bigEndian
fileData.append(Data(bytes: &offset, count: 4))
fileData.append(Data(bytes: &blockSize, count: 4))

// PCM data
for sample in samples {
    var s = sample.bigEndian
    fileData.append(Data(bytes: &s, count: 2))
}

try fileData.write(to: url)
print("OK")
SOUNDSWIFT

swiftc "$BUILD_DIR/build/make_sound.swift" -o "$BUILD_DIR/build/make_sound"
"$BUILD_DIR/build/make_sound" "$BUILD_DIR/build/complete.aiff"
echo "✓ 提示音生成完成"

# ---- 3. 编译主程序 ----
echo "→ 编译主程序..."
swiftc \
    -parse-as-library \
    -O \
    -target arm64-apple-macosx15.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    -framework UserNotifications \
    -o "$BUILD_DIR/build/$APP_NAME" \
    "$BUILD_DIR/Sources/main.swift"

echo "✓ 编译完成"

# ---- 4. 创建 .app 包 ----
echo "→ 打包应用..."

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS"
mkdir -p "$OUTPUT/Contents/Resources"

# 可执行文件
cp "$BUILD_DIR/build/$APP_NAME" "$OUTPUT/Contents/MacOS/"

# 图标
cp "$BUILD_DIR/build/AppIcon.icns" "$OUTPUT/Contents/Resources/"

# 提示音
cp "$BUILD_DIR/build/complete.aiff" "$OUTPUT/Contents/Resources/"

# Info.plist
cat > "$OUTPUT/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.pomodoro.local</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Pomodoro 番茄时钟</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# PkgInfo
echo -n 'APPL????' > "$OUTPUT/Contents/PkgInfo"

echo "✓ 应用打包完成"

# ---- 5. 签名（可选，本地运行不需要） ----
# codesign --force --deep --sign - "$OUTPUT"

echo ""
echo "=============================================="
echo "  ✅ 编译成功！"
echo "  应用程序位置: $OUTPUT"
echo "  双击图标即可打开"
echo "=============================================="

# 移到 Applications 目录询问
echo ""
read -p "要安装到 /Applications 目录吗？[y/N] " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$OUTPUT" "/Applications/"
    echo "✓ 已安装到 /Applications"
fi
