# VMware Workstation 汉化工具

![Platform](https://img.shields.io/badge/platform-Windows%2010%2B-0078D6?logo=windows&logoColor=white)
![Architecture](https://img.shields.io/badge/arch-x64-555555)
![Flutter](https://img.shields.io/badge/Flutter-3.13%2B-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)
![Interface](https://img.shields.io/badge/interface-%E4%B8%AD%E6%96%87%20%7C%20English-4C5BD4)
![Package](https://img.shields.io/badge/package-single%20exe-2E9E6B)

把 VMware Workstation Pro 26.0.1 的界面汉化为简体中文，并可一键还原为备份。

## 为什么需要它

VMware 按系统语言选择界面，但它的语言判断只认三种：

| 系统语言 | 实际界面 |
|---|---|
| 西班牙语 / 法语 / 日语 | 各自语言 |
| 简体中文 | 英文 |
| 其他 | 英文 |

简体中文不在判断列表中，所以中文系统只能显示英文。本工具把中文补进这个判断，并安装中文语言包。

> 汉化生效后日语界面将不可用，还原即恢复。

## 功能

- **一键汉化**：写入 45 字节改动并安装中文语言包
- **一键还原**：回到原始英文界面，删除新增的语言文件
- **写入安全**：改动前校验文件哈希，逐字节检查前置值，原子替换，任何不符即中止

## 使用

运行 `VMwareLocalizer-portable.exe`，按提示操作。写入安装目录需要管理员权限，程序会自动请求提权。

## 构建

```bash
cd app
flutter pub get
flutter build windows --release

cd ..
pwsh tool/build_portable_exe.ps1
```

第一条命令生成可运行目录，第二条把它打包为单个 exe。

## 测试

```bash
cd app
flutter test
```

## 系统要求

- Windows 10 或更高版本
- VMware Workstation Pro 26.0.1
- 从源码构建需 Flutter 3.13+ 与 Visual Studio（C++ 桌面开发工作负载）
