# 复制本文件为同目录下的 local.secrets.ps1 并填入真实密钥（该文件已被 .gitignore 排除，不会上传 GitHub）
# 作用：本机手动运行 automation/update_data.ps1 时自动加载
# GitHub Actions 端则改用仓库 Settings > Secrets and variables > Actions 配置（见 README 第一节）
$env:JD_APP_KEY_A = "填入KEY-A"
$env:JD_APP_SECRET_A = "填入SECRET-A"
$env:JD_APP_KEY_B = "填入KEY-B"
$env:JD_APP_SECRET_B = "填入SECRET-B"
