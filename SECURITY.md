# 安全说明

## 这个仓库里没有密钥

本仓库只有文档、脚本和日志摘录，**不包含** API Key、访问令牌、账号密码、私有证书，
也不包含模型权重或引擎二进制（`.gitignore` 已排除）。

如果你发现任何一处疑似凭据或个人路径，请直接开 issue（或按下面的方式私下报告）。

## 报告问题

- **敏感信息泄露 / 安全问题**：用 GitHub 的
  [Private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities)
  （仓库 Security 标签页 → Report a vulnerability），不要开公开 issue。
- **文档错误、跑不通、数字对不上**：正常开 issue，附上你的硬件与引擎版本。

这是一个个人项目，不承诺响应时间。

## 使用这些脚本前请知道

1. **`strata/patches/` 会改第三方工具的文件。** 它只做「在函数定义前插入 + 在调用点插一行」，
   并且 `-Check` 是默认动作；但打补丁前请先看清 `strata/patches/README.md`，出问题用 `-Revert`。
2. **`gpu_power` 补丁会弹 UAC。** 它只执行写死的 `nvidia-smi`，参数只接受整数，
   不创建计划任务、不写注册表、不装服务。取消 UAC 就什么都没发生。
3. **脚本会重启本地的 Strata 服务**（`strata launch --stop` / `--restart`）。
   别在正在跑任务的机器上随手执行 bench。
4. **证据日志是摘录，不是完整日志。** 完整日志在 `%LOCALAPPDATA%\Strata\launch\`，
   里面含个人路径，**不要**直接提交。

## 支持范围

只针对仓库里记录的版本组合做过验证：

| 项 | 版本 |
| --- | --- |
| Strata | 0.2.6（Terminal 0.1.51 / engine 0.1.50） |
| 系统 | Windows 11 |
| GPU | RTX 4080 16 GB，驱动 580+ |

其它版本可能能用，但没测过。
