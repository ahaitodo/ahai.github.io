# lyej.cn · 蓝牙耳机优选（京东联盟 CPS 导购站）

只做蓝牙耳机垂类的省钱导购站。**日常零人工**：GitHub Actions 每天自动从京东联盟接口抓爆款 → 转推广链接 → 更新榜单上线。

```
┌─────────────┐   每天 00:20/08:20/16:20(北京)   ┌──────────────┐
│ GitHub Action │ ── 调京东联盟API(密钥在Secrets) ──▶ │ data/products.json │
└─────────────┘                                  └──────┬───────┘
                                                        │ commit 触发重建
                                                        ▼
                              GitHub Pages (lyej.cn)  静态站自动更新
                                                        │
                                          访客点击 u.jd.com 推广链接下单
                                                        │
                                              佣金结算到联盟账号 10170
```

**安全设计**：appKey/appSecret 只存在 GitHub Secrets 和本地 `local.secrets.ps1`（已 gitignore），永远不会出现在网页代码里——静态站全公开，密钥入页等于送钱。

---

## 一、部署 SOP（一次性，约 20 分钟）

### 1. 建 GitHub 仓库
github.com → New repository → 起名（如 `lyej`）→ **Public**（Pages 免费版必须公开）→ 不要勾选任何初始化选项。

### 2. 上传文件（无 git 也能传）
仓库页 → **uploading an existing file** → 把本目录（`lyej-site`）里的**全部内容**拖进去：
- 注意 `.github` 文件夹、`.nojekyll`、`CNAME` 这些隐藏/无后缀文件必须一起传（Windows 资源管理器开"显示隐藏项目"）。
- 传完确认仓库里有 `.github/workflows/update-data.yml`。
- `automation/local.secrets.ps1` **不要传**（本地测试专用，含密钥）。

### 3. 配置密钥
仓库 → Settings → Secrets and variables → Actions → New repository secret，逐个添加：

| Secret 名 | 值 |
|---|---|
| `JD_APP_KEY_A` | 你的 KEY-A（appKey，已私下提供，勿写进任何公开文件） |
| `JD_APP_SECRET_A` | 你的 SECRET-A（appSecret） |
| `JD_APP_KEY_B` | 你的 KEY-B |
| `JD_APP_SECRET_B` | 你的 SECRET-B |
| `JD_SITE_ID_WEBSITE` | （先留空，见"转链通道"） |

> ⚠️ appKey/appSecret 属于账户资产：只放 GitHub Secrets 和本机 `automation/local.secrets.ps1`（已 gitignore）。任何写进公开仓库/网页代码的行为都等于把佣金管道交给别人用；若怀疑泄露，立即到京东联盟开放平台重置密钥。

### 4. 开启 Pages
Settings → Pages → Build and deployment → Source 选 **Deploy from a branch** → Branch 选 `main` + `/ (root)` → Save。
然后 Custom domain 填 `lyej.cn` → Save；等 DNS 校验通过后勾选 **Enforce HTTPS**。

### 5. 解析域名
到你的域名注册商处，把 DNS 改成 GitHub Pages 的：

- 裸域 `lyej.cn` → A 记录 4 条：`185.199.108.153` `185.199.109.153` `185.199.110.153` `185.199.111.153`
- `www` → CNAME → `你的用户名.github.io`

解析生效（几分钟到几小时）后访问 https://www.lyej.cn 即可。

### 6. 首次跑数据
仓库 → Actions → `update-deals` → **Run workflow**。跑完看 `data/products.json` 是否有商品；同时 Pages 会自动部署最新榜单。

---

## 二、转链通道：现状与解锁

推广链接 = 钱的管道。当前状态（2026-11-01 实测）：

| 通道 | 状态 | 说明 |
|---|---|---|
| `promotion.common.get`（网站/APP渠道） | ✅ 代码就绪 | 需要一个**网站类型**的推广位 siteId，填入 Secret `JD_SITE_ID_WEBSITE` 即全通 |
| `promotion.bysubunionid.get`（社交媒体渠道） | ⛔ 403 | 你的渠道 10170 是社媒类，此 API 需在联盟开放平台**申请权限** |
| `manual-links.json`（手工转链） | ✅ 随时可用 | 联盟后台手动转的链接填进来，优先级最高 |

**三条解锁路（按推荐排序）**：

1. **建网站推广位（最优，2分钟）**：若 lyej.cn 有 ICP 备案号 → 联盟后台（union.jd.com）→ 推广管理 → 新建网站推广 → 填域名+备案号 → 拿到网站ID 填进 Secret `JD_SITE_ID_WEBSITE` → 全自动化转链 permanent。
2. **申请社媒API权限**：union.jd.com → 开放平台 → `jd.union.open.promotion.bysubunionid.get` 文档页 → 申请权限（审核时间不确定，通过后代码自动生效，无需改动）。
3. **临时手工**：联盟后台 → 链接转换工具，把热门商品的链接转出来 → 按格式填 `data/manual-links.json`：
   ```json
   { "100012043978": "https://u.jd.com/xxxxxx" }
   ```
   商品没转链时，站上按钮会退化为"复制名称去京东搜"并走你的兜底首页链接（仍带佣金归属）。

> 未转链的商品**绝不发裸链**（item.jd.com 直链没有佣金，等于白送京东流量）。

---

## 三、日常运维 = 0

- Actions 每天 00:20（北京，配额重置后）、08:20、16:20 各跑一次；任何改动自动 commit + 部署。
- 手动补跑：Actions → update-deals → Run workflow。
- 换品/调价位：改 `automation/config.json`（关键词、价位段、筛选阈值）提交即可。
- 突发：联盟改接口导致某天数据为空？看 Actions 日志里 `last_run` 输出的错误码，对照本文末尾的"错误码速查"。

---

## 四、双11运营手册（人来做的部分：搬运流量）

**现金账先算清**：蓝牙耳机佣金率约 2%-6%，客单 100-300 元 → **一单赚 3-15 元**。"几千元" ≈ 300-800 单。站只是转化器，钱在流量里。以下动作每天 10 分钟：

### 1. 你身边现成的渠道（当天见效）
- **老板同学 & 他的顾客群**：他说你"守着金矿"，那就拉他入伙——他实体店的顾客微信群正是精准流量。给他的话术："双11 买耳机先领券再凑单，一单省 50+，群里发这个链接就行。"
- **朋友圈**：直接转发站内链接 + 一句"双11耳机底价清单，跨店满300减50，先领券"。
- **同学群/小区群/家长群**：不要刷屏，11.11 当天 0 点、20 点两个节点各发一次。

### 2. 内容平台（长尾流量，每晚一条）
- **知乎**：回答"2026年有什么蓝牙耳机推荐""预算300蓝牙耳机怎么选"，末尾挂 lyej.cn 榜单（"每日更新的榜单在这里"）。知乎+耳机=长常青流量。
- **小红书**：图文"双11耳机红黑榜"，标题带"双11 蓝牙耳机"，图用站内榜单截图。
- **贴吧/论坛**：耳机吧、数码吧，回复求推荐贴。
- 事实核查提醒：文案别写"全网最低价""第一"等极限词（广告法红线），写"到手价一目了然""先领券再凑单"这类实词。

### 3. 双11 节奏（2026 京东规则：现货长跑 + 跨店每满300减50 + 官方直降）
| 时间 | 动作 |
|---|---|
| 现在-11.9 | 每天转发一次榜单；知乎/小红书铺 3-5 篇内容攒长尾 |
| 11.10 晚 8 点 | 第二波爆发点：群里发"秒杀整点开抢" |
| 11.11 当天 | 0 点、10 点、20 点三轮转发；朋友圈晒"XX 已下单"截图带链接 |
| 11.12-11.15 | 发"价保最后几天，买贵退差价"——信任感拉满，返场单照样算你的佣金 |

### 3.5 红包链路（转化率最高的入口，重点推）
已配置三个**无门槛京享红包**入口 + 蓝牙耳机专场页（均为已转链的固定链接，带你的联盟归属）：
- 红包① `https://u.jd.com/e1yc6hI`
- 红包② `https://u.jd.com/eOy9Gbh`
- 红包③ `https://u.jd.com/ery4LHV`
- 耳机专场 `https://u.jd.com/eDyg1pj`（蓝牙耳机搜索结果页，站内金色主按钮）

**转发话术**："京东11.11又好又便宜——先点这三个链接把红包都领了（无门槛，下单直接抵），再去买耳机，红包+跨店满300减50+品类券三重叠加。"
这些链接配置在 `automation/config.json` 的 `activities` 里（`"fixed": true` 标记，管线直接使用、不会重复转链）。

### 4. 看数据
联盟后台（union.jd.com）→ 效果报表 → 订单明细。重点看：点击数 → 转化率 → 佣金。哪个价位段出单多，第二天把 `config.json` 里对应段位的 `cap` 调大。

---

## 五、文件结构

```
lyej-site/
├── index.html            # 首页：红包+倒计时+分价位榜单+场景+凑单+FAQ
├── guides.html           # 选购指南（常青内容，SEO 主力）
├── tao.html              # 淘拼好货：全屏嵌入大淘客页（淘宝/拼多多渠道）
├── assets/               # 样式与渲染脚本（无依赖，全静态）
├── data/
│   ├── products.json     # ★ 管线输出，站点唯一数据源
│   ├── manual-links.json # 手工转链（可选，优先级最高）
│   └── linkcache.json    # 转链缓存（自动生成，gitignore）
├── automation/
│   ├── update_data.ps1   # ★ 数据管线（本机/Actions 通用）
│   ├── config.json       # 关键词/价位段/筛选规则/固定活动链接
│   └── local.secrets.ps1 # 本地密钥（绝不提交）
├── llms.txt              # AI/LLM 站点说明（引用授权、数据入口）
├── ai.txt                # AI 系统使用说明（内容边界、爬取建议）
├── robots.txt            # 爬虫协议（AI 爬虫白名单）
├── sitemap.xml           # 站点地图（直接版）
├── sitemap_index.xml     # 站点地图索引
├── sitemap1.xml          # 站点地图明细（sitemap_index 指向）
└── .github/workflows/update-data.yml  # ★ 定时任务
```

## 七、AI 与搜索爬虫适配

五个入口 + robots 配套，让搜索引擎和 AI 助手（ChatGPT/豆包/Perplexity 等）正确收录并引用本站——AI 问答里被引用 = 免费精准流量：

| 文件 | 作用 |
|---|---|
| `/llms.txt` | LLM 站点说明（llmstxt.org 规范）：站点定位、页面清单、数据入口、引用授权 |
| `/ai.txt` | AI 系统使用说明：内容边界、时效性说明、推荐爬取方式 |
| `/sitemap.xml` | 站点地图（三页全量） |
| `/sitemap_index.xml` | 站点地图索引（指向 sitemap1.xml，未来页面多了好扩展） |
| `/sitemap1.xml` | 站点地图明细（lastmod 随大促更新） |

robots.txt 已对 GPTBot / ClaudeBot / PerplexityBot / 字节 Bytespider 等 13 个 AI 爬虫显式放行；以后若不想被某家抓取，在 robots.txt 里把对应段落的 `Allow: /` 改成 `Disallow: /` 即可。

上线后建议：把 `https://www.lyej.cn/sitemap_index.xml` 提交到 [Google Search Console](https://search.google.com/search-console)、百度站长平台、必应站长工具各一次，收录速度翻倍。

## 六、错误码速查

| 错误 | 含义 | 处理 |
|---|---|---|
| `2000 已达接口调用上限` | 当日配额用尽 | 等北京时间 0 点重置；A/B 两个 key 会自动切换 |
| `1002001 无此应用信息` | appKey 未在联盟注册 | 检查密钥是否复制完整 |
| `2001701 不支持siteId` | 渠道类型不匹配（社媒≠网站） | 见"转链通道"三选一 |
| `403 无访问权限` | API 未申请权限（秒杀/社媒转链） | 联盟后台申请，或忽略（已降级处理） |
| `62 json conversion error` | 参数编码问题 | 管线已内置 \uXXXX 转义，不会出现 |
