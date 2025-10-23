# Sui Move Trading Sample App

## 動かし方

### インストール

```bash
pnpm i
```

### フォーマッター適用

```bash
pnpm run biome:format
```

### Sui CLIで自分のアドレスを確認する方法

```bash
sui client addresses
```

### 環境変数のセットアップ

```bash
cp pkgs/api/.env.example pkgs/api/.env
```

### データベースのセットアップ

```bash
pnpm api run db:setup:dev
```

以下のようになればOK!

```bash
Prisma schema loaded from prisma/schema.prisma
Datasource "db": SQLite database "dev.db" at "file:./dev.db"

SQLite database dev.db created at file:./dev.db

Applying migration `20240122110930_init`
Applying migration `20240129111604_init`

The following migration(s) have been applied:

migrations/
  └─ 20240122110930_init/
    └─ migration.sql
  └─ 20240129111604_init/
    └─ migration.sql

Your database is now in sync with your schema.

✔ Generated Prisma Client (v5.22.0) to ./../../node_modules/.pnpm/@prisma+client@5.22.0_prisma@5.22.0/node_m
odules/@prisma/client in 112ms
```

データベースをリセットしたい時は以下のコマンドを実行する

```bash
pnpm api run db:reset:dev
```

### スマートコントラクトのビルド

以下のフォルダに移動してそれぞれでビルドコマンドを実施

- `pkgs/contracts/demo`
- `pkgs/contracts/escrow`

```bash
sui move build
```

### スマートコントラクトを公開

```bash
pnpm api run deploy
```

### ロックされていないオブジェクトとロックされたオブジェクトのデモを生成

```bash
pnpm api run create-demo-data
```

### デモのエスクローを生成する

```bash
pnpm api run create-demo-escrows
```

### APIとインデクサーを両方起動

```bash
pnpm api dev
```

### フロントエンドビルド

```bash
pnpm frontend build
```

### フロントエンド起動

```bash
pnpm frontend dev -- --host
```