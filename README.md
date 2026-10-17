# 轻投票：GitHub Pages + Supabase

一个白色简约风的自定义投票网站，支持投票标题/描述/时间、候选人和照片链接、排行榜、管理员 CRUD、账号登录，以及数据库层面的每账号每投票限一票。

## 技术与安全说明

- 前端静态托管到 GitHub Pages；数据库与邮箱/密码认证由 Supabase 承担。
- `SUPABASE_ANON_KEY`（publishable/anon key）是前端公开配置，不是管理员密钥。**绝不要将 `service_role` / secret key 放入 `app.js` 或提交到 GitHub。**
- 所有表都启用 RLS；管理员身份由 `admin_users` 表确定；唯一约束 `unique(poll_id,user_id)` 在数据库层防止重复投票。数据库触发器还会校验候选人属于该投票且投票处于开放时间。
- 投票者必须注册并登录邮箱账号，才能投票。这样是“每个账号一票”，不是“每个现实的人绝对一票”；用户仍可能创建多个账号。需要更强防刷时，应加验证码、限流或邀请码。
- 为保护投票人隐私，普通用户只能读取自己的 vote 行；排行榜通过 `public_vote_counts` 聚合视图展示总票数，不公开 voter user_id。

## 1. 创建 Supabase 项目

1. 打开 <https://supabase.com/> 并创建项目，记下数据库密码（妥善保存）。
2. 进入 **SQL Editor**，新建查询，将本仓库 `supabase.sql` 全文粘贴并执行。
3. 进入 **Project Settings → API**（部分界面显示 API Keys），复制 Project URL 和 publishable/anon key。
4. 编辑 `app.js` 开头两行：

```js
const SUPABASE_URL = 'https://你的项目ID.supabase.co';
const SUPABASE_ANON_KEY = '你的 publishable 或 anon key';
```

此 key 会出现在浏览器里，属于正常设计；安全性依赖 RLS。不要使用 `service_role` / secret key。

## 2. 配置邮箱认证

Supabase Dashboard → **Authentication → Providers → Email**，启用 Email provider。测试时可按需要配置是否要求邮箱验证。生产环境建议保持邮箱验证开启，并配置正确的 Site URL / Redirect URLs（你的 GitHub Pages URL）。

## 3. 添加管理员

1. 在网站上注册一个账号，按设置完成邮箱验证。
2. 在 Supabase → **Authentication → Users** 找到该用户，复制 UUID。
3. 在 SQL Editor 执行（将 UUID 替换成实际值）：

```sql
insert into public.admin_users (user_id)
values ('这里替换成你的 Auth 用户 UUID')
on conflict (user_id) do nothing;
```

4. 回到网页重新登录。管理员账号会看到“管理后台”按钮。普通用户不能自行将自己设为管理员。

## 4. 发布到 GitHub Pages

1. 在 GitHub 新建一个公开仓库，例如 `vote-site`。
2. 将本目录里的 `index.html`、`style.css`、`app.js`、`supabase.sql`、`README.md` 上传到仓库根目录。
3. 打开仓库 **Settings → Pages**。
4. 在 **Build and deployment** 中选择 **Deploy from a branch**，分支选择 `main`，目录选择 `/ (root)`，保存。
5. 等待 GitHub Pages 部署完成，访问显示的 `https://你的用户名.github.io/vote-site/`。
6. 回 Supabase → Authentication URL Configuration，将这个地址添加到 **Site URL** 和允许的 **Redirect URLs**。修改 `app.js` 后，提交 GitHub 即可自动更新网页。

也可以直接在手机浏览器打开 GitHub 仓库，上传这些文件；但修改 `app.js` 建议使用 GitHub 网页编辑器或电脑操作，避免引号被自动替换。

## 5. 使用方式

- 管理员登录 → 管理后台 → 创建投票。
- 在“已有投票”中点击“候选人”，添加姓名、简介和照片 URL；照片需要是可公开访问的 HTTPS 图片地址。
- 设置是否发布、开始时间、结束时间；复制浏览器地址栏里的投票链接分享给朋友（形如 `.../#poll-投票ID`）。
- 投票者注册/登录后，在每个投票中选择一位候选人。数据库唯一约束阻止同一账号对同一投票重复提交。

## 运行和排错

- 网页显示“还差最后一步配置”：检查 `app.js` 的 URL / anon key 是否已替换。
- `Invalid login credentials`：确认账号已注册、邮箱验证已完成，且密码正确。
- `permission denied` 或加载失败：确认已执行 SQL，检查表 RLS policies，以及 Supabase Auth URL 配置。
- 照片不显示：使用可公开访问的 HTTPS 图片直链；不能使用需要登录或有防盗链限制的页面地址。
- GitHub Pages 是静态托管，不能安全存放后端密钥；本方案不需要把数据库密码或 service role key 放入前端。
