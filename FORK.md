# MiniClarc — fork 总览

> **MiniClarc** (`dttxorg/MiniClarc`) 是一个**独立维护的硬分叉**版本,基于
> [ttnear/Clarc](https://github.com/ttnear/Clarc)。本仓库与上游共享同一份
> Apache License 2.0 协议,但**走自己的版本号、发版节奏和路线图**,不依赖
> 上游合并 PR。

---

## 1. 来源与致谢

MiniClarc 的全部原始代码、UI 设计、协议和大部分架构决策来自上游
[ttnear/Clarc](https://github.com/ttnear/Clarc)。我们对原作者
[ttnear](https://github.com/ttnear) 表示衷心感谢 —— 没有上游的扎实工作,
这个分叉不会存在。

按 Apache License 2.0 §4 的要求:
- ✅ 完整 LICENSE 文本随每一次分发附带(`/LICENSE`)
- ✅ 所有修改过的文件头部加注 "Modifications Copyright ... SPDX-License-Identifier: Apache-2.0"
- ✅ 上游 URL 在 Settings → 开源 面板中明示
- ✅ 不会使用 `ttnear` / `Clarc` 商标暗示原作者为本分叉背书

详见 [`NOTICE`](./NOTICE) 文件。

---

## 2. 跟上游的差异(分叉增量)

> **注意**:跟上游的差异**累积**而不是替代。每一次 release 都在前一次基础上叠加。

| 起始版本 | 增量 | commit | 说明 |
|---|---|---|---|
| v1.3.2-fork.4 | (从 feat/auto-approve-in-project-root 沿用) | `b26f613`..`a420e20` | on-request auto-approval + Bash 白名单扩展 + 16 工具 |
| v1.3.2-fork.4 | 本地化修复 | `7b8b0d6` | PermissionModal 倒计时 + Settings 权限描述 |
| v1.3.2-fork.4 | 全权限模式 | `cb43709` | `PermissionMode.fullAccess` + CLI 通配符 `--allowedTools "*"` |
| v1.3.2-fork.4 | 3 档 UX 改进 | `2a82354` | 阶段式折叠 + fold 阈值 + Focus Mode 修复 |
| v1.3.2-fork.4 | 编译可见性修复 | `a420e20` | `MessageGroup` 改 `internal`,让 CI 通过 |
| **v2.0.0** | **本分叉的 1.0 版** | (即将提交) | 项目身份重塑:`com.idealapp.Clarc` → `com.dttxorg.MiniClarc`,display name → "MiniClarc",Sparkle feed 切到 `dttxorg/MiniClarc`,Settings 链接组重排,加 `NOTICE` 文件 |

### v2.0.0 之后会怎么演进

- 走自己的版本号(`v2.x.y`)
- 不再定期 rebase 上游;只在有价值时 cherry-pick
- 上游合并的新功能**不**自动同步,需要时单独评估
- 自己的路线图:本地化优先、UI 体验、可观测性

---

## 3. 安装(从分叉 release 下载)

1. 打开 [Releases 页面](https://github.com/dttxorg/MiniClarc/releases)
2. 下载最新的 `Clarc-2.x.y.zip`(注意:不再是 `Clarc-x.y.z-fork.n.zip`)
3. 解压后把 `MiniClarc.app`(注意:不是 `Clarc.app`)拖到 `/Applications`
4. **bundle id 是 `com.dttxorg.MiniClarc`**,跟上游 `com.idealapp.Clarc` 不冲突,可以共存
5. 首次启动:**右键 `MiniClarc.app` → Open** 确认 Gatekeeper 弹窗(ad-hoc 签名,无 notarize)
6. 之后双击即可

---

## 4. 更新(分叉内的版本升级)

`SUFeedURL` 已切到 `https://raw.githubusercontent.com/dttxorg/MiniClarc/main/appcast.xml`。
Sparkle 会检查本仓库 `main` 分支的 `appcast.xml`。

**注意:** `SUPublicEDKey` 暂时为空(原值是上游 ttnear 的 EdDSA 公钥,不能复用)。这意味着:
- 应用内"检查更新"按钮仍能拉到本分叉的新版本
- 但**没有签名校验**,用户需要自己确认下载源(`dttxorg/MiniClarc` GitHub Releases)
- 待本地生成新的 EdDSA keypair 后(用 `scripts/setup_sparkle.sh`),把新公钥填回 `Clarc/Info.plist` 的 `SUPublicEDKey` 即可开启签名校验

如果你从分叉 v1.x 升级到 v2.x,因为 bundle id 改了,**两个版本可以并存**,不会互相覆盖。

---

## 5. 构建

### 5.1 CI(fork 专用)

`.github/workflows/fork-build.yml` 在 push `v*` tag 时自动跑:
- macos-15 runner,Xcode 16.4+
- `xcodebuild` Release 配置 + ad-hoc 签名 (`CODE_SIGN_IDENTITY=-`)
- `ditto -c -k --norsrc --noextattr --noqtn` 打包 zip
- 上传 artifact + 创建 draft release

### 5.2 手动触发本地构建(需要 macOS + Xcode)

```bash
open Clarc.xcodeproj   # Cmd+R 直接 run
# 或者
xcodebuild -project Clarc.xcodeproj -scheme Clarc -configuration Release build
```

打包:
```bash
# (上游 build_zip.sh 走 notarize,需要 Apple Developer ID;fork 不走那条路)
# 直接用 CI 同款的 ditto:
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "MiniClarc.app" -path "*Release*" -type d | head -n1)
mkdir -p build
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP_PATH" build/Clarc-2.0.0.zip
```

### 5.3 打 tag 触发 CI

```bash
git tag v2.0.0
git push origin v2.0.0
```

`workflow_dispatch` 也可以手动触发(在 GitHub Actions 页面上)。

---

## 6. 跟上游的协作(可选)

虽然 MiniClarc 走独立路线,我们**欢迎**把分叉内有价值的改动提 PR 回上游:
- i18n 修复、bug fix、UX 改进 —— 跟上游 PR #16 类似
- 协议层的改动(`PermissionMode.fullAccess`、阶段式折叠) —— 上游未必感兴趣
- 项目身份重塑 —— 显然只属于本分叉

回 PR 的流程:**先把 `feat/...` rebase 到上游 `main`**,再开 PR。这是单独的工作流,不阻塞 MiniClarc 自己的发版。

---

## 7. License

Apache License 2.0,与上游一致。完整文本见 [`LICENSE`](./LICENSE),
修改声明见 [`NOTICE`](./NOTICE)。
</content>
</invoke>