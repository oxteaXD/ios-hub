// 识别截图里的文字，逐张打印出来。冒烟测试用它把「屏幕上显示了什么」变成文字写进测试结果，
// 这样不用下载截图也能判断界面对不对。
//
// 用法：xcrun swift scripts/ocr.swift 截图1.png 截图2.png ...

import Foundation
import ImageIO
import Vision

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let name = url.deletingPathExtension().lastPathComponent

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        print("[\(name)] 读不出这张图片")
        continue
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false

    do {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        print("[\(name)] 屏幕上的文字（\(lines.count) 行）：")
        for line in lines {
            print("    " + line)
        }
    } catch {
        print("[\(name)] 文字识别失败：\(error)")
    }
}
