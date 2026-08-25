# mac-init

这是一套面向当前电脑的 Apple Silicon Mac 初始化配置。

当前基线：MacBook Pro（M2 Pro）、macOS 26、原生 arm64 环境。工程只管理
`/opt/homebrew`，不再使用 Intel Homebrew、固定版本下载地址或 GUI 自动化脚本。

## 主要变化

- Homebrew 固定使用 Apple Silicon 官方前缀 `/opt/homebrew`。
- 恢复并精简 `Brewfile`，移除 Python 3.9/3.10、OpenSSL 1.1、Qt 5、GCC 10、
  MySQL 5.7 等版本化历史依赖。
- Go、Maven 改由 Homebrew 安装；Node LTS 由 `fnm` 管理；Rust stable 由
  `rustup` 管理；Python 版本由 `pyenv` 按项目选择。
- Shell 配置使用可更新的托管区块；修改前自动备份现有文件，不会整份覆盖。
- Git 用户名和邮箱不再硬编码；已有设置会保留。
- Dock 和 Finder 设置直接使用 `defaults`，不依赖界面语言和旧版
  “System Preferences”。
- 不自动删除 `/usr/local` 下的旧 Homebrew，避免误删仍被旧项目使用的数据。
- MinIO 客户端、tap 和本地配置已从当前基线中移除。

## 使用

先查看当前状态：

```sh
./run.sh --check
```

执行初始化：

```sh
./run.sh
```

默认只安装缺失的软件，不主动升级已经安装的软件。需要升级 Brewfile 中的软件时：

```sh
./run.sh --upgrade
```

可用选项：

```text
--check                 只检查，不修改电脑
--upgrade               同时升级已有 Homebrew 软件
--skip-macos-defaults   不修改 Dock 和 Finder 设置
--skip-dotfiles         不修改 zsh 配置，也不安装 .vimrc
--skip-apps             跳过桌面应用和 VS Code 扩展
```

如果是全新电脑且 Git 身份尚未配置，可以在首次运行时传入：

```sh
GIT_USER_NAME="your-name" GIT_USER_EMAIL="you@example.com" ./run.sh
```

脚本完成后打开一个新终端，再运行 `./run.sh --check`。

## 运行时策略

- Node.js：脚本安装并选中最新 LTS。项目仍应提交自己的 `.node-version`。
- Python：脚本只安装 `pyenv`，不替项目猜测 Python 版本。例如：
  `pyenv install 3.14 && pyenv global 3.14`。
- Rust：首次运行时安装 stable toolchain。
- Java：使用当前 Oracle JDK cask；`JAVA_HOME` 由 macOS 的
  `/usr/libexec/java_home` 解析，不再硬编码目录。
- Go：使用 Homebrew 当前稳定版，并保留当前电脑使用的
  `GOPROXY=https://goproxy.cn,direct`。

## 从旧 Intel 配置迁移

当前电脑已完成 `/usr/local` Intel Homebrew 的卸载，并切换到 `/opt/homebrew`。其他旧
电脑迁移时，shell 配置中常见这些历史路径：

- `/usr/local/go`
- `/usr/local/opt/mysql@5.7`、`openssl@1.1`
- JDK 8、Maven 3.6.2、GCC 10
- Intel 版 zsh-autosuggestions

脚本会检测并报告它们，但不会自动删除。先运行新配置并确认所有项目正常，再从
`~/.zshrc`、`~/.zprofile` 和 `~/.bash_profile` 中移除对应旧行。最后如确定不再需要
Intel Homebrew，按照 [Homebrew 官方卸载说明](https://github.com/Homebrew/install#uninstall-homebrew)
针对 `/usr/local` 单独卸载；不要直接删除整个 `/usr/local`。

这台电脑已有不少由旧 Homebrew 或手动安装的 App。首次迁移建议先运行
`./run.sh --skip-apps`；清理或迁移这些 App 后，再运行完整的 `./run.sh`。全新电脑可
直接运行完整脚本。

## 维护 Brewfile

Homebrew Bundle 是滚动更新的软件清单，不锁定具体版本。检查清单是否满足：

```sh
/opt/homebrew/bin/brew bundle check --no-upgrade --file=./Brewfile
```

如需采集当前安装状态作为比较材料，可输出到临时文件，不要直接覆盖已整理的清单：

```sh
/opt/homebrew/bin/brew bundle dump --force --file=/tmp/Brewfile.current
diff -u Brewfile /tmp/Brewfile.current
```

参考：[Homebrew 安装说明](https://docs.brew.sh/Installation)、
[Homebrew Bundle 与 Brewfile](https://docs.brew.sh/Brew-Bundle-and-Brewfile)。
