# 照片批量导入

适用于 iOS 16 或更新版本。打开 App，点「选择文件夹并导入」，在「文件」选择装照片的文件夹。允许添加照片并保持 App 在前台。完成后可在系统「照片」查看。

App 会包含子文件夹，每批最多 16 张，以原始图片文件资源添加到「照片」。如果一批提交失败，会逐个重试并显示失败项目。从 v1.5 开始，App 按文件内容自动跳过重复导入，即使文件改名或换了目录。实况照片需要静态图片与配套 MOV 的内容都相同。旧版导入的记录在原路径再次扫描时会补上内容指纹。导入和记录之间若被强制退出，最近一批可能重复。App 不读取相册内容，因此无法识别之前通过其他方式导入的照片。实况照片需要保留原始图片和配套 MOV。App 按内嵌标识自动配对，支持文件改名。只有静态图片时会按普通照片导入。旧版本已经导入的静态副本会留在相册，新版可把对应的完整实况照片另存一次。

## 用 Mac 安装到自己的 iPhone

1. 用 Xcode 打开 PhotoImport.xcodeproj，连接并信任 iPhone。
2. 选 PhotoImport target，进入 Signing & Capabilities，启用 Automatically manage signing，选择自己的 Team。如 Bundle Identifier 被占用，改成自己的唯一标识。
3. 在 Xcode 选择这台 iPhone 并点 Run。若手机提示启用开发者模式，按系统提示完成。
4. 如需导出 IPA，用有相应分发权限的开发者团队，在 Xcode 选择 Product → Archive，在 Organizer 根据相应分发方式签名和导出。

当前交付是 Xcode 源码。生成和验证签名 IPA 需要 macOS、Xcode 和适用于目标 iPhone 的签名。
